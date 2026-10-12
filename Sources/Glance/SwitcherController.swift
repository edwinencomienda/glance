import AppKit
import Carbon.HIToolbox

@MainActor
final class SwitcherController {
    /// How long a dragged item must hover a tile before that window comes forward.
    private static let springLoadDelay: TimeInterval = 0.45

    private enum Key {
        static let tab: Int64 = 48, escape: Int64 = 53, returnKey: Int64 = 36, enter: Int64 = 76
        static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
        static let grave: Int64 = 50
    }

    private enum Action: UInt32 {
        case forward = 1, backward, cancel, commit, left, right, up, down
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
    /// Registered only while the switcher is open (the modifier is held, so it's
    /// part of the combo).
    private static let sessionHotkeys: [(Action, Int, Int)] = [
        (.cancel, kVK_Escape, 0),
        (.commit, kVK_Return, 0),
        (.left, kVK_LeftArrow, 0),
        (.right, kVK_RightArrow, 0),
        (.up, kVK_UpArrow, 0),
        (.down, kVK_DownArrow, 0),
    ]

    private let settings = Settings.shared
    /// The shortcut currently registered; changes go through `applyShortcut()`.
    private var shortcut = Settings.shared.shortcut

    private let model = SwitcherModel()
    private let thumbnails = ThumbnailService()
    private let hotkeys = GlobalHotkeys()
    private let mru = WindowMRU()
    private lazy var panel = SwitcherPanel(
        model: model,
        onHover: { [weak self] in self?.hover(at: $0) },
        onClick: { [weak self] in self?.click(at: $0) },
        onDragHover: { [weak self] in self?.dragHover(at: $0) }
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
    private var screen: NSScreen?
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
        for (action, _, _) in Self.triggerHotkeys { hotkeys.unregister(id: action.rawValue) }
        shortcut = settings.shortcut
        for (action, key, mods) in Self.triggerHotkeys {
            hotkeys.register(id: action.rawValue, keyCode: key, modifiers: mods | shortcut.carbonModifier)
        }
        NativeSwitcher.setEnabled(shortcut != .commandTab)
    }

    func stop() {
        NativeSwitcher.setEnabled(true)
    }

    // MARK: - Keyboard

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let flags = event.flags
        switch type {
        case .flagsChanged:
            if isActive && !isDragMode && !flags.contains(shortcut.eventFlag) { commit() }
            return false

        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            // In drag mode the modifier may already be released, so a bare ⇥ keeps cycling.
            if key == Key.tab && (flags.contains(shortcut.eventFlag) || isActive) {
                perform(flags.contains(.maskShift) ? .backward : .forward, from: .tap)
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
        case .cancel: close()
        case .commit: commit()
        case .left: step(-1)
        case .right: step(1)
        case .up: step(-model.layout.columns)
        case .down: step(model.layout.columns)
        }
    }

    // MARK: - Lifecycle

    private func open(reverse: Bool) {
        let listed = WindowList.current(includeOtherSpaces: settings.spacesScope == .all,
                                        excluding: Set(settings.excludedBundleIDs))
        let windows = mru.order(current: listed.current, others: listed.others)
        guard !windows.isEmpty else { return }
        isActive = true
        isDragMode = NSEvent.pressedMouseButtons & 1 != 0

        let screen = Self.screenUnderMouse()
        self.screen = screen
        let iconsOnly = settings.displayStyle == .icons
        let layout = SwitcherLayout.make(count: windows.count, in: screen.visibleFrame.size,
                                         thumbWidth: iconsOnly ? settings.thumbnailSize.iconTileWidth
                                                               : settings.thumbnailSize.width,
                                         showTitles: settings.showTitles,
                                         iconsOnly: iconsOnly)

        model.windows = windows
        model.layout = layout
        model.thumbnails = iconsOnly ? [:] : thumbnails.cached(for: windows)
        model.selected = windows.count > 1 ? (reverse ? windows.count - 1 : 1) : 0

        // Warm AX lookups for other-Space windows so switching to one is instant.
        let otherIDs = Set(listed.others.map(\.id))
        WindowFocus.prefetch(windows.filter { otherIDs.contains($0.id) }, live: Set(windows.map(\.id)))

        // Icon mode captures nothing at all.
        if !iconsOnly {
            thumbnails.refresh(windows, maxSize: layout.thumbSize, scale: screen.backingScaleFactor) { [weak self] id, image in
                self?.model.thumbnails[id] = image
            }
        }

        showTimer = Timer.scheduledTimer(withTimeInterval: settings.showDelayMs / 1000, repeats: false) { [weak self] _ in
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

    private func pollInputState() {
        guard isActive else { return }
        let commandHeld = CGEventSource.flagsState(.combinedSessionState).contains(shortcut.eventFlag)
        if isDragMode {
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
        for (action, _, _) in Self.sessionHotkeys { hotkeys.unregister(id: action.rawValue) }
        panel.orderOut(nil)
    }

    // MARK: - Mouse

    private func hover(at point: CGPoint) {
        guard isActive, let index = model.layout.index(at: point) else { return }
        if model.selected != index { model.selected = index }
    }

    private func click(at point: CGPoint) {
        guard isActive, let index = model.layout.index(at: point) else { return }
        model.selected = index
        commit()
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

    private static func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
