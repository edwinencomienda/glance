import AppKit
import ApplicationServices

// Maps an AX window element to its CGWindowID (HIServices, stable for many macOS releases).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

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
    typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    static let setFrontProcess = sym("_SLPSSetFrontProcessWithOptions", as: SetFrontFn.self)
    static let postEventRecord = sym("SLPSPostEventRecordTo", as: PostEventFn.self)
    static let setSymbolicHotKeyEnabled = sym("CGSSetSymbolicHotKeyEnabled", as: SymbolicHotKeyFn.self)
    // GetProcessForPID is deprecated (not removed); look it up dynamically to avoid the warning.
    static let getProcessForPID: GetPSNFn? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let p = dlsym(h, "GetProcessForPID") else { return nil }
        return unsafeBitCast(p, to: GetPSNFn.self)
    }()
}

/// The native ⌘⇥ / ⌘⇧⇥ / ⌘` switcher hotkeys, which we disable while running.
enum NativeSwitcher {
    private static let hotkeys: [Int32] = [1, 2] // commandTab, commandShiftTab

    static func setEnabled(_ enabled: Bool) {
        guard let fn = SkyLight.setSymbolicHotKeyEnabled else { return }
        for key in hotkeys { _ = fn(key, enabled) }
    }
}

enum WindowFocus {
    private static let queue = DispatchQueue(label: "glance.focus", qos: .userInteractive)

    /// Brings a specific window to front. Runs off the main thread so a hung app
    /// can never stall the switcher UI.
    static func focus(_ window: WindowInfo) {
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
            raise(window)
        }
    }

    private static func raise(_ window: WindowInfo) {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return }
        for axWindow in axWindows {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &id) == .success, id == window.id {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
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
