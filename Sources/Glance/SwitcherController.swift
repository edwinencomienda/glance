import AppKit

@MainActor
final class SwitcherController {
    /// A quick ⌘⇥ tap switches without ever drawing the panel (like Windows).
    private static let showDelay: TimeInterval = 0.07

    private enum Key {
        static let tab: Int64 = 48, escape: Int64 = 53, returnKey: Int64 = 36, enter: Int64 = 76
        static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
        static let grave: Int64 = 50
    }

    private let model = SwitcherModel()
    private let thumbnails = ThumbnailService()
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
    private var screen: NSScreen?

    func start() -> Bool {
        _ = panel // build the view hierarchy now, not on first ⌘⇥
        guard tap.start() else { return false }
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
                let reverse = flags.contains(.maskShift)
                isActive ? step(reverse ? -1 : 1) : open(reverse: reverse)
                return true
            }
            guard isActive else { return false }
            switch key {
            case Key.escape: close()
            case Key.returnKey, Key.enter: commit()
            case Key.left, Key.grave: step(-1)
            case Key.right: step(1)
            case Key.up: step(-model.layout.columns)
            case Key.down: step(model.layout.columns)
            default: break
            }
            return true // swallow everything while the switcher is up

        case .keyUp:
            return isActive

        default:
            return false
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
    }

    private func present() {
        guard isActive, let screen else { return }
        panel.show(size: model.layout.panelSize, on: screen)
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
