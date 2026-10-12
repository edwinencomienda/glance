import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = SwitcherController()
    private var statusItem: NSStatusItem?
    private var started = false
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        installSignalHandlers()

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startSwitcher()
        } else {
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Glance")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Glance — ⌘⇥ to switch windows", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        addPermission(to: menu, title: "Accessibility", granted: AXIsProcessTrusted(),
                      pane: "Privacy_Accessibility")
        addPermission(to: menu, title: "Screen Recording", granted: CGPreflightScreenCaptureAccess(),
                      pane: "Privacy_ScreenCapture")
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func addPermission(to menu: NSMenu, title: String, granted: Bool, pane: String) {
        let item = NSMenuItem(title: "\(title): \(granted ? "Granted" : "Grant…")",
                              action: granted ? nil : #selector(openSettings(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = pane
        item.image = NSImage(systemSymbolName: granted ? "checkmark.circle.fill" : "exclamationmark.circle",
                             accessibilityDescription: nil)
        menu.addItem(item)
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let pane = sender.representedObject as? String,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Glance: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
