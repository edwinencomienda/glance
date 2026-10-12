import AppKit
import Carbon.HIToolbox

@MainActor
final class SwitcherController {
    /// A quick ⌘⇥ tap switches without ever drawing the panel (like Windows).
    private static let showDelay: TimeInterval = 0.07

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

    /// Always registered: the trigger.
    private static let triggerHotkeys: [(Action, Int, Int)] = [
        (.forward, kVK_Tab, cmdKey),
        (.backward, kVK_Tab, cmdKey | shiftKey),
    ]
    /// Registered only while the switcher is open (⌘ is held, so ⌘ is part of the combo).
    private static let sessionHotkeys: [(Action, Int, Int)] = [
        (.cancel, kVK_Escape, cmdKey),
        (.commit, kVK_Return, cmdKey),
        (.left, kVK_LeftArrow, cmdKey),
        (.right, kVK_RightArrow, cmdKey),
        (.up, kVK_UpArrow, cmdKey),
        (.down, kVK_DownArrow, cmdKey),
    ]

    private let model = SwitcherModel()
    private let thumbnails = ThumbnailService()
    private let hotkeys = GlobalHotkeys()
    private lazy var panel = SwitcherPanel(
        model: model,
        onHover: { [weak self] in self?.hover(at: $0) },
        onClick: { [weak self] in self?.click(at: $0) }
    )
    private lazy var tap = HotkeyTap { type, event in
        MainActor.assumeIsolated { self.handle(type, event) }
    }

    private var isActive = false
    private var showTimer: Timer?
    private var modifierTimer: Timer?
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
        for (action, key, mods) in Self.triggerHotkeys {
            hotkeys.register(id: action.rawValue, keyCode: key, modifiers: mods)
        }
        NativeSwitcher.setEnabled(false)
        return true
    }

    func stop() {
        NativeSwitcher.setEnabled(true)
    }

    // MARK: - Keyboard

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let flags = event.flags
        switch type {
        case .flagsChanged:
            if isActive && !flags.contains(.maskCommand) { commit() }
            return false

        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if key == Key.tab && flags.contains(.maskCommand) {
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
        let windows = WindowList.current()
        guard !windows.isEmpty else { return }
        isActive = true

        let screen = Self.screenUnderMouse()
        self.screen = screen
        let layout = SwitcherLayout.make(count: windows.count, in: screen.visibleFrame.size)

        model.windows = windows
        model.layout = layout
        model.thumbnails = thumbnails.cached(for: windows)
        model.selected = windows.count > 1 ? (reverse ? windows.count - 1 : 1) : 0

        thumbnails.refresh(windows, maxSize: layout.thumbSize, scale: screen.backingScaleFactor) { [weak self] id, image in
            self?.model.thumbnails[id] = image
        }

        showTimer = Timer.scheduledTimer(withTimeInterval: Self.showDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.present() }
        }

        // The tap can't see ⌘ being released under Secure Event Input, so also watch
        // the modifier state, only while the switcher is open (never at idle).
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) { self?.commit() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    private func present() {
        guard isActive, let screen else { return }
        panel.show(size: model.layout.panelSize, on: screen)
        // Registered here rather than in open() so a quick tap never pays for them.
        for (action, key, mods) in Self.sessionHotkeys {
            hotkeys.register(id: action.rawValue, keyCode: key, modifiers: mods)
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
        if let target { WindowFocus.focus(target) }
    }

    private func close() {
        isActive = false
        showTimer?.invalidate()
        showTimer = nil
        modifierTimer?.invalidate()
        modifierTimer = nil
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

    private static func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
