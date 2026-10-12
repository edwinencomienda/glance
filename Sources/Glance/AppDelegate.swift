import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = SwitcherController()
    private let settings = Settings.shared
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var started = false
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        installSignalHandlers()
        settings.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .shortcut: if self.started { self.switcher.applyShortcut() }
            case .menuBarIcon: self.statusItem?.isVisible = self.settings.showMenuBarIcon
            }
        }

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startSwitcher()
        } else {
            // First run: show Settings so the Permissions section explains what's needed.
            settingsWindow.show()
            // Wait for the user to grant Accessibility, then start without a relaunch.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard AXIsProcessTrusted() else { return }
                    self?.startSwitcher()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        switcher.stop()
    }

    /// Launching Glance again while it runs opens Settings. This is the way back
    /// in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    private func startSwitcher() {
        guard !started, switcher.start() else { return }
        started = true
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    /// Always hand ⌘⇥ back to macOS, even when killed from the terminal.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = settings.showMenuBarIcon
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Glance — \(settings.shortcut.symbol) to switch windows", action: nil, keyEquivalent: "")
            .isEnabled = false
        if !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() {
            let warning = NSMenuItem(title: "Permissions Needed…", action: #selector(showSettings), keyEquivalent: "")
            warning.target = self
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(warning)
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }
}
