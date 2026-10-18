import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class SwitcherController {
    /// How long a dragged item must hover a tile before that window comes forward.
    private static let springLoadDelay: TimeInterval = 0.45
    /// In drag mode the panel waits at least this long before appearing. Releasing ⌘
    /// before then is a quick switch: it commits like a normal ⌘⇥ tap and the drag
    /// carries on into the new window, with no panel flash.
    private static let dragTapGrace: TimeInterval = 0.25
    /// The same-app switcher usually lists only a few windows, so its tiles start
    /// this much larger (the layout still shrinks them to fit the screen).
    private static let appModeTileScale: CGFloat = 1.3

    private enum Key {
        static let tab: Int64 = 48, escape: Int64 = 53, returnKey: Int64 = 36, enter: Int64 = 76
        static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
        static let grave: Int64 = 50
        static let w: Int64 = 13, q: Int64 = 12
    }

    private enum Action: UInt32 {
        case forward = 1, backward, cancel, commit, left, right, up, down
        /// Modifier + ` / ⇧`: only the frontmost app's windows.
        case appForward, appBackward
        /// W closes the selected window, Q quits its app.
        case closeWindow, quitApp
    }

    /// Input arrives from two paths: the event tap (full keyboard, but blind while
    /// Secure Event Input is on) and registered hotkeys (work everywhere, exact
    /// combos only). Both feed `perform`, which drops the duplicate if one press
    /// is ever reported by both.
    private enum Source { case tap, hotkey }

    /// Always registered: the trigger. Combined with the shortcut's modifier.
    private static let triggerHotkeys: [(Action, Int, Int)] = [
        (.forward, kVK_Tab, 0),
        (.backward, kVK_Tab, shiftKey),
    ]
    /// Registered when the same-app switcher is on.
    private static let appHotkeys: [(Action, Int, Int)] = [
        (.appForward, kVK_ANSI_Grave, 0),
        (.appBackward, kVK_ANSI_Grave, shiftKey),
    ]
    /// Registered only while the switcher is open (the modifier is held, so it's
    /// part of the combo).
    private static let sessionHotkeys: [(Action, Int, Int)] = [
        (.cancel, kVK_Escape, 0),
        (.commit, kVK_Return, 0),
        (.left, kVK_LeftArrow, 0),
        (.right, kVK_RightArrow, 0),
        (.up, kVK_UpArrow, 0),
        (.down, kVK_DownArrow, 0),
        (.closeWindow, kVK_ANSI_W, 0),
        (.quitApp, kVK_ANSI_Q, 0),
    ]

    private let settings = Settings.shared
    /// The shortcut currently registered; changes go through `applyShortcut()`.
    private var shortcut = Settings.shared.shortcut
    private var appWindowsShortcut = false

    private let model = SwitcherModel()
    private let thumbnails = ThumbnailService()
    private let hotkeys = GlobalHotkeys()
    private let mru = WindowMRU()
    private lazy var panel = SwitcherPanel(
        model: model,
        onHover: { [weak self] in self?.hover(at: $0) },
        onClick: { [weak self] in self?.click(at: $0) },
        onDragHover: { [weak self] in self?.dragHover(at: $0) },
        onExit: { [weak self] in self?.mouseExited() }
    )
    private lazy var tap = HotkeyTap { type, event in
        MainActor.assumeIsolated { self.handle(type, event) }
    }

    private var isActive = false
    private var showTimer: Timer?
    private var modifierTimer: Timer?
    private var springTimer: Timer?
    private var springIndex: Int?
    /// The drag has hovered `springIndex` long enough; it switches once ⌘ is up.
    private var springArmed = false
    /// Opened while the mouse button was held (dragging a file, text, …). The panel
    /// then stays open after ⌘ is released so you can hover the drag over a tile.
    private var isDragMode = false
    /// The panel has been ordered in (the show delay has passed).
    private var isShown = false
    /// Opened with modifier + `: only the frontmost app's windows are listed.
    private var isAppMode = false
    private var screen: NSScreen?
    /// What `open` built the layout from, so it can be rebuilt when tiles go away.
    private var tileWidth: CGFloat = 0
    /// Every window this switcher listed, in order, and those whose tiles were
    /// closed but aren't confirmed gone yet.
    private var sessionWindows: [WindowInfo] = []
    private var hiddenIDs: Set<CGWindowID> = []
    /// Bumped on every open, so late close checks can't touch a newer switcher.
    private var sessionID = 0
    private var lastAction: (action: Action, source: Source, time: TimeInterval)?

    func start() -> Bool {
        _ = panel // build the view hierarchy now, not on first ⌘⇥
        guard tap.start() else { return false }
        hotkeys.onPress = { [weak self] id in
            MainActor.assumeIsolated {
                if let action = Action(rawValue: id) { self?.perform(action, from: .hotkey) }
            }
        }
        applyShortcut()
        return true
    }

    /// Registers the trigger for the chosen shortcut. ⌘⇥ replaces the native
    /// switcher, so that's disabled; ⌥⇥ leaves the native one alone.
    func applyShortcut() {
        close()
        for (action, _, _) in Self.triggerHotkeys + Self.appHotkeys { hotkeys.unregister(id: action.rawValue) }
        shortcut = settings.shortcut
        appWindowsShortcut = settings.appWindowsShortcut
        let triggers = Self.triggerHotkeys + (appWindowsShortcut ? Self.appHotkeys : [])
        for (action, key, mods) in triggers {
            hotkeys.register(id: action.rawValue, keyCode: key, modifiers: mods | shortcut.carbonModifier)
        }
        NativeSwitcher.setEnabled(shortcut != .commandTab)
        NativeSwitcher.setWindowCyclingEnabled(!(appWindowsShortcut && shortcut == .commandTab))
    }

    func stop() {
        NativeSwitcher.setEnabled(true)
        NativeSwitcher.setWindowCyclingEnabled(true)
    }

    // MARK: - Keyboard

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let flags = event.flags
        switch type {
        case .flagsChanged:
            if isActive && !flags.contains(shortcut.eventFlag) && (!isDragMode || !isShown) { commit() }
            return false

        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            // In drag mode the modifier may already be released, so a bare ⇥ keeps cycling.
            if key == Key.tab && (flags.contains(shortcut.eventFlag) || isActive) {
                perform(flags.contains(.maskShift) ? .backward : .forward, from: .tap)
                return true
            }
            if key == Key.grave && appWindowsShortcut && flags.contains(shortcut.eventFlag)
                && (!isActive || isAppMode) {
                perform(flags.contains(.maskShift) ? .appBackward : .appForward, from: .tap)
                return true
            }
            guard isActive else { return false }
            switch key {
            case Key.escape: perform(.cancel, from: .tap)
            case Key.returnKey, Key.enter: perform(.commit, from: .tap)
            case Key.left, Key.grave: perform(.left, from: .tap)
            case Key.right: perform(.right, from: .tap)
            case Key.up: perform(.up, from: .tap)
            case Key.down: perform(.down, from: .tap)
            case Key.w: perform(.closeWindow, from: .tap)
            case Key.q: perform(.quitApp, from: .tap)
            default: break
            }
            return true // swallow everything while the switcher is up

        case .keyUp:
            return isActive

        default:
            return false
        }
    }

    private func perform(_ action: Action, from source: Source) {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastAction, last.action == action, last.source != source, now - last.time < 0.05 {
            return
        }
        lastAction = (action, source, now)

        switch action {
        case .forward: isActive ? step(1) : open(reverse: false)
        case .backward: isActive ? step(-1) : open(reverse: true)
        case .appForward: isActive ? step(1) : open(reverse: false, appOnly: true)
        case .appBackward: isActive ? step(-1) : open(reverse: true, appOnly: true)
        case .cancel: close()
        case .commit: commit()
        case .left: step(-1)
        case .right: step(1)
        case .up: step(-model.layout.columns)
        case .down: step(model.layout.columns)
        case .closeWindow: if isActive && isShown { closeOrQuit(model.selected, quit: false) }
        case .quitApp: if isActive && isShown { closeOrQuit(model.selected, quit: true) }
        }
    }

    // MARK: - Lifecycle

    private func open(reverse: Bool, appOnly: Bool = false) {
        var listed = WindowList.current(includeOtherSpaces: settings.spacesScope == .all,
                                        excluding: Set(settings.excludedBundleIDs))
        // NSWorkspace keeps this up to date itself; reading it is no IPC.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Every window that still exists, taken before the same-app and display
        // filters. Caches are pruned against this, so a filtered switcher doesn't
        // evict the thumbnails and AX elements of the windows it hides.
        let live = Set(listed.current.map(\.id)).union(listed.others.map(\.id))
        if appOnly {
            guard let frontPID else { return }
            listed.current.removeAll { $0.pid != frontPID }
            listed.others.removeAll { $0.pid != frontPID }
        }
        var windows = mru.order(current: listed.current, others: listed.others)

        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        let screen = panelScreen(screens: screens, frames: frames, current: listed.current, frontPID: frontPID)
        if settings.currentDisplayOnly, screens.count > 1, let index = screens.firstIndex(of: screen) {
            windows.removeAll { Displays.screenIndex(for: $0.bounds, in: frames) != index }
        }
        guard !windows.isEmpty else { return }
        isActive = true
        isAppMode = appOnly
        isDragMode = NSEvent.pressedMouseButtons & 1 != 0
        self.screen = screen
        let iconsOnly = settings.displayStyle == .icons
        let baseWidth = iconsOnly ? settings.thumbnailSize.iconTileWidth : settings.thumbnailSize.width
        tileWidth = (baseWidth * (appOnly ? Self.appModeTileScale : 1)).rounded()
        let layout = makeLayout(count: windows.count, on: screen)

        sessionID += 1
        sessionWindows = windows
        hiddenIDs = []
        model.windows = windows
        model.layout = layout
        model.thumbnails = iconsOnly ? [:] : thumbnails.cached(for: windows)
        model.selected = windows.count > 1 ? (reverse ? windows.count - 1 : 1) : 0

        // Warm AX lookups for other-Space windows so switching to one is instant.
        let otherIDs = Set(listed.others.map(\.id))
        WindowFocus.prefetch(windows.filter { otherIDs.contains($0.id) }, live: live)

        // Icon mode captures nothing at all.
        if !iconsOnly {
            thumbnails.refresh(windows, live: live, maxSize: layout.thumbSize, scale: screen.backingScaleFactor) { [weak self] id, image in
                self?.model.thumbnails[id] = image
            }
        }

        // A drag gets a longer grace so a quick ⌘⇥ switches instead of opening the panel.
        var showDelay = settings.showDelayMs / 1000
        if isDragMode { showDelay = max(showDelay, Self.dragTapGrace) }
        showTimer = Timer.scheduledTimer(withTimeInterval: showDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.present() }
        }

        // Watch input state only while the switcher is open (never at idle): ⌘ release,
        // which the tap can't see under Secure Event Input, or the end of a drag.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollInputState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    private func makeLayout(count: Int, on screen: NSScreen) -> SwitcherLayout {
        SwitcherLayout.make(count: count, in: screen.visibleFrame.size, thumbWidth: tileWidth,
                            showTitles: settings.showTitles, iconsOnly: settings.displayStyle == .icons)
    }

    private func pollInputState() {
        guard isActive else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let commandHeld = flags.contains(shortcut.eventFlag)
        let quitMode = flags.contains(shortcut.quitFlag)
        if model.quitMode != quitMode { model.quitMode = quitMode }
        if isDragMode && !isShown {
            // Still in the quick-tap window: behave like a normal ⌘⇥.
            if !commandHeld {
                commit()
            } else if NSEvent.pressedMouseButtons & 1 == 0 {
                isDragMode = false // the drag ended first; carry on as a normal switcher
            }
        } else if isDragMode {
            if NSEvent.pressedMouseButtons & 1 == 0 {
                dragEnded()
            } else if springArmed && !commandHeld {
                commit()
            }
        } else if !commandHeld {
            commit()
        }
    }

    private func present() {
        guard isActive, let screen else { return }
        isShown = true
        panel.show(size: model.layout.panelSize, on: screen)
        // Registered here rather than in open() so a quick tap never pays for them.
        for (action, key, mods) in Self.sessionHotkeys {
            hotkeys.register(id: action.rawValue, keyCode: key, modifiers: mods | shortcut.carbonModifier)
        }
    }

    private func step(_ delta: Int) {
        let n = model.windows.count
        guard n > 0 else { return }
        model.selected = ((model.selected + delta) % n + n) % n
    }

    private func commit() {
        guard isActive else { return }
        let target = model.windows.indices.contains(model.selected) ? model.windows[model.selected] : nil
        close()
        if let target {
            mru.touch(target.id)
            WindowFocus.focus(target)
        }
    }

    private func close() {
        isActive = false
        showTimer?.invalidate()
        showTimer = nil
        modifierTimer?.invalidate()
        modifierTimer = nil
        springTimer?.invalidate()
        springTimer = nil
        springIndex = nil
        springArmed = false
        isDragMode = false
        isShown = false
        isAppMode = false
        model.hovered = nil
        model.buttonHot = false
        model.quitMode = false
        sessionWindows = []
        hiddenIDs = []
        for (action, _, _) in Self.sessionHotkeys { hotkeys.unregister(id: action.rawValue) }
        panel.orderOut(nil)
    }

    // MARK: - Mouse

    private func hover(at point: CGPoint) {
        guard isActive, !isDragMode else { return }
        let hit = model.layout.hit(at: point)
        let hovered = hit?.index, hot = hit.map { if case .button = $0 { true } else { false } } ?? false
        if model.hovered != hovered { model.hovered = hovered }
        if model.buttonHot != hot { model.buttonHot = hot }
        if let hovered, model.selected != hovered { model.selected = hovered }
    }

    private func mouseExited() {
        model.hovered = nil
        model.buttonHot = false
    }

    private func click(at point: CGPoint) {
        guard isActive, let hit = model.layout.hit(at: point) else { return }
        model.selected = hit.index
        if case .button(let index) = hit {
            closeOrQuit(index, quit: model.quitMode)
        } else {
            commit()
        }
    }

    // MARK: - Close & quit

    private static let closeAnimation = 0.2

    /// Closes the window at `index`, or quits its app. The tile goes away straight
    /// away and the switcher stays open, so you can close several in a row. If the
    /// window turns out to still be open (no close button, a cancelled "Save
    /// changes?", an app that refused to quit), its tile comes back.
    private func closeOrQuit(_ index: Int, quit: Bool) {
        guard model.windows.indices.contains(index) else { return }
        let window = model.windows[index]
        let session = sessionID
        if quit {
            guard WindowFocus.quit(pid: window.pid) else { NSSound.beep(); return }
            let ids = Set(model.windows.filter { $0.pid == window.pid }.map(\.id))
            hide(ids)
            confirmGone(ids, session: session, checks: [0.5, 1.5, 4])
        } else {
            hide([window.id])
            WindowFocus.close(window) { [weak self] pressed in
                guard let self, self.isActive, self.sessionID == session else { return }
                if pressed {
                    self.confirmGone([window.id], session: session, checks: [0.5, 1.5, 3])
                } else {
                    NSSound.beep()
                    self.unhide([window.id])
                }
            }
        }
    }

    /// Re-lists windows after each delay. Uses the switcher's own window list, not
    /// mere existence: many apps keep a closed window around off screen instead of
    /// destroying it. Windows still listed at the last check get their tiles back.
    private func confirmGone(_ ids: Set<CGWindowID>, session: Int, checks: [TimeInterval]) {
        for (n, delay) in checks.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isActive, self.sessionID == session else { return }
                let pending = ids.intersection(self.hiddenIDs)
                guard !pending.isEmpty else { return }
                let listed = WindowList.current(includeOtherSpaces: self.settings.spacesScope == .all,
                                                excluding: Set(self.settings.excludedBundleIDs))
                let still = pending.intersection(Set(listed.current.map(\.id)).union(listed.others.map(\.id)))
                // Gone for good: forget them, so a later restore can't bring them back.
                self.sessionWindows.removeAll { pending.subtracting(still).contains($0.id) }
                self.hiddenIDs.subtract(pending.subtracting(still))
                if n == checks.count - 1, !still.isEmpty { self.unhide(still) }
            }
        }
    }

    private func hide(_ ids: Set<CGWindowID>) {
        hiddenIDs.formUnion(ids)
        updateTiles()
    }

    private func unhide(_ ids: Set<CGWindowID>) {
        hiddenIDs.subtract(ids)
        updateTiles()
    }

    /// Shows `sessionWindows` minus the hidden ones, animating tiles out (or back
    /// in) and the panel to its new size.
    private func updateTiles() {
        let visible = sessionWindows.filter { !hiddenIDs.contains($0.id) }
        guard visible.map(\.id) != model.windows.map(\.id) else { return }
        guard !visible.isEmpty, let screen else { close(); return }
        let selectedID = model.windows.indices.contains(model.selected) ? model.windows[model.selected].id : nil
        let layout = makeLayout(count: visible.count, on: screen)
        withAnimation(.easeOut(duration: Self.closeAnimation)) {
            model.windows = visible
            model.layout = layout
            model.selected = visible.firstIndex { $0.id == selectedID } ?? min(model.selected, visible.count - 1)
            // Tiles moved; the next mouse move puts the button back under the pointer.
            model.hovered = nil
            model.buttonHot = false
        }
        if isShown { panel.resize(to: layout.panelSize, duration: Self.closeAnimation) }
    }

    // MARK: - Drag & drop (spring-loading)

    private func dragHover(at point: CGPoint?) {
        guard isActive else { return }
        let index = point.flatMap { model.layout.index(at: $0) }
        if let index, model.selected != index { model.selected = index }
        guard index != springIndex else { return }

        springIndex = index
        springArmed = false
        springTimer?.invalidate()
        springTimer = nil
        guard index != nil else { return }
        // Arm only; the input poll switches once ⌘ is released, so the window never
        // jumps forward while you're still holding the shortcut.
        springTimer = Timer.scheduledTimer(withTimeInterval: Self.springLoadDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.springArmed = true }
        }
    }

    /// The drag finished: dropped on a tile focuses that window; anywhere else cancels.
    private func dragEnded() {
        if let point = panel.contentPoint(fromScreen: NSEvent.mouseLocation),
           let index = model.layout.index(at: point) {
            model.selected = index
            commit()
        } else {
            close()
        }
    }

    /// The display the panel appears on: under the pointer, or the one holding the
    /// active window (the frontmost app's front window), falling back to the pointer.
    private func panelScreen(screens: [NSScreen], frames: [CGRect],
                             current: [WindowInfo], frontPID: pid_t?) -> NSScreen {
        if settings.panelDisplay == .activeWindow, screens.count > 1,
           let active = current.first(where: { $0.pid == frontPID }) ?? current.first,
           let index = Displays.screenIndex(for: active.bounds, in: frames) {
            return screens[index]
        }
        return Self.screenUnderMouse()
    }

    private static func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
