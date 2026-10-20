import AppKit
import ApplicationServices


/// Private SkyLight entry points, resolved at runtime so a missing symbol degrades
/// gracefully to public APIs instead of crashing at launch.
enum SkyLight {
    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func sym<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    typealias SymbolicHotKeyFn = @convention(c) (Int32, Bool) -> CGError
    typealias IsSymbolicHotKeyFn = @convention(c) (Int32) -> Bool
    typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    typealias MainConnectionFn = @convention(c) () -> Int32
    typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias ManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    static let setFrontProcess = sym("_SLPSSetFrontProcessWithOptions", as: SetFrontFn.self)
    static let postEventRecord = sym("SLPSPostEventRecordTo", as: PostEventFn.self)
    static let setSymbolicHotKeyEnabled = sym("CGSSetSymbolicHotKeyEnabled", as: SymbolicHotKeyFn.self)
    static let isSymbolicHotKeyEnabled = sym("CGSIsSymbolicHotKeyEnabled", as: IsSymbolicHotKeyFn.self)
    static let mainConnection = sym("CGSMainConnectionID", as: MainConnectionFn.self)
    static let copySpacesForWindows = sym("CGSCopySpacesForWindows", as: SpacesForWindowsFn.self)
    static let copyManagedDisplaySpaces = sym("CGSCopyManagedDisplaySpaces", as: ManagedDisplaySpacesFn.self)
    // GetProcessForPID is deprecated (not removed); look it up dynamically to avoid the warning.
    static let getProcessForPID: GetPSNFn? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let p = dlsym(h, "GetProcessForPID") else { return nil }
        return unsafeBitCast(p, to: GetPSNFn.self)
    }()
}

/// The native ⌘⇥ / ⌘⇧⇥ / ⌘` switcher hotkeys, which we disable while running.
///
/// macOS can turn them back on behind our back (seen on macOS 27). Normally the
/// event tap swallows ⌘⇥ first, so nobody notices, but under Secure Event Input
/// (a focused password field) the tap is blind and the native switcher wins.
/// `reassert()` puts back the state we asked for; it's called on app activation,
/// wake and Dock relaunch, never on the ⌘⇥ path or from a timer.
@MainActor
enum NativeSwitcher {
    private static let hotkeys: [Int32] = [1, 2] // commandTab, commandShiftTab
    private static let windowCycling: Int32 = 27 // ⌘`: move focus to the app's next window

    /// The state we last asked for, keyed by symbolic hotkey id.
    private static var wanted: [Int32: Bool] = [:]

    static func setEnabled(_ enabled: Bool) {
        for key in hotkeys { set(key, enabled) }
    }

    /// The native ⌘` window cycling, replaced by Glance's same-app switcher.
    static func setWindowCyclingEnabled(_ enabled: Bool) {
        set(windowCycling, enabled)
    }

    /// Re-applies the wanted state to any hotkey macOS has flipped. Only hotkeys
    /// we disabled are checked: restoring an enabled one is never urgent.
    static func reassert() {
        guard let setFn = SkyLight.setSymbolicHotKeyEnabled else { return }
        for (key, enabled) in wanted where !enabled {
            if let isFn = SkyLight.isSymbolicHotKeyEnabled {
                guard isFn(key) else { continue }
                NSLog("Glance: native symbolic hotkey \(key) was re-enabled by the system; disabling it again")
            }
            _ = setFn(key, false)
        }
    }

    private static func set(_ key: Int32, _ enabled: Bool) {
        wanted[key] = enabled
        guard let fn = SkyLight.setSymbolicHotKeyEnabled else { return }
        _ = fn(key, enabled)
    }
}

enum WindowFocus {
    private static let queue = DispatchQueue(label: "glance.focus", qos: .userInteractive)
    /// Close requests get their own queue so they never wait behind `prefetch`'s
    /// lookups of windows on other Spaces.
    private static let closeQueue = DispatchQueue(label: "glance.close", qos: .userInteractive)

    /// Brings a specific window to front, switching Spaces if it lives on another
    /// one. Runs off the main thread so a hung app can never stall the switcher UI.
    static func focus(_ window: WindowInfo) {
        if window.pid == ProcessInfo.processInfo.processIdentifier {
            DispatchQueue.main.async {
                NSApp.activate()
                NSApp.windows.first { $0.windowNumber == Int(window.id) }?.makeKeyAndOrderFront(nil)
            }
            return
        }
        queue.async {
            var psn = ProcessSerialNumber()
            if let getPSN = SkyLight.getProcessForPID, let setFront = SkyLight.setFrontProcess,
               getPSN(window.pid, &psn) == noErr {
                _ = setFront(&psn, window.id, 0x200) // kCPSUserGenerated
                makeKeyWindow(&psn, window.id)
            } else {
                DispatchQueue.main.async {
                    NSRunningApplication(processIdentifier: window.pid)?.activate()
                }
            }
            // Raising the window's AX element is what makes macOS switch to its
            // Space; the window-server calls above don't, and neither does app
            // activation from a background process.
            guard let element = AXWindowResolver.element(for: window) else { return }
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    /// Closes a window by pressing its own close button, exactly as a click on it
    /// would, so the app can still ask to save changes. Runs on the focus queue;
    /// `done` gets `false` on the main thread if the window has no close button.
    static func close(_ window: WindowInfo, done: @escaping @MainActor (Bool) -> Void) {
        if window.pid == ProcessInfo.processInfo.processIdentifier {
            DispatchQueue.main.async {
                let own = NSApp.windows.first { $0.windowNumber == Int(window.id) }
                own?.performClose(nil)
                MainActor.assumeIsolated { done(own != nil) }
            }
            return
        }
        closeQueue.async {
            var pressed = false
            if let element = AXWindowResolver.element(for: window) {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &value) == .success,
                   let button = value, CFGetTypeID(button) == AXUIElementGetTypeID() {
                    pressed = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(pressed) } }
        }
    }

    /// Asks an app to quit, the same as choosing Quit from its menu, so it can still
    /// ask to save changes. Never quits Glance itself.
    @MainActor
    static func quit(pid: pid_t) -> Bool {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.terminate()
    }

    /// Resolves AX elements for windows on other Spaces ahead of time (called when
    /// the switcher opens, in MRU order), so choosing one doesn't wait for a token
    /// scan. Also forgets elements of windows that no longer exist.
    static func prefetch(_ windows: [WindowInfo], live: Set<CGWindowID>) {
        queue.async {
            AXWindowResolver.prune(keeping: live)
            for window in windows { _ = AXWindowResolver.element(for: window) }
        }
    }

    /// Synthesizes the window-server "make key" event pair so the exact window
    /// (not just the app) receives focus.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
        guard let post = SkyLight.postEventRecord else { return }
        var wid = windowID
        for kind: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xF8)
            bytes[0x04] = 0xF8
            bytes[0x08] = kind
            bytes[0x3A] = 0x10
            withUnsafeBytes(of: &wid) { src in
                for i in 0..<4 { bytes[0x3C + i] = src[i] }
            }
            for i in 0x20..<0x30 { bytes[i] = 0xFF }
            bytes.withUnsafeMutableBufferPointer { _ = post(&psn, $0.baseAddress!) }
        }
    }
}
