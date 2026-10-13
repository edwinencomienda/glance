import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Finds the Accessibility element for a `CGWindowID`.
///
/// `kAXWindowsAttribute` only lists an app's windows on the current Space, so a
/// window on another Space (including a full-screen one) has no reachable
/// element, and without one we can't raise it, which is what switches Spaces.
/// For those, rebuild the element from a remote token (pid + "coco" + element
/// id) and scan element ids until one maps to the window.
/// Results are cached. Only call this on `WindowFocus`'s queue.
enum AXWindowResolver {
    private static var cache: [CGWindowID: AXUIElement] = [:]
    private static let maxElementID: UInt64 = 6000
    private static let scanBudget: TimeInterval = 0.2
    private static let messagingTimeout: Float = 0.1

    private typealias RemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private static let createWithRemoteToken: RemoteTokenFn? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let p = dlsym(h, "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(p, to: RemoteTokenFn.self)
    }()

    static func element(for window: WindowInfo) -> AXUIElement? {
        if let cached = cache[window.id] {
            if windowID(of: cached) == window.id { return cached }
            cache[window.id] = nil
        }
        let element = fromWindowList(window) ?? fromRemoteTokens(window)
        if let element { cache[window.id] = element }
        return element
    }

    /// Drops cached elements for windows that no longer exist.
    static func prune(keeping ids: Set<CGWindowID>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    private static func isWindow(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success
            && role as? String == kAXWindowRole
    }

    private static func fromWindowList(_ window: WindowInfo) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { windowID(of: $0) == window.id }
    }

    private static func fromRemoteTokens(_ window: WindowInfo) -> AXUIElement? {
        guard let create = createWithRemoteToken else { return nil }
        let deadline = Date().addingTimeInterval(scanBudget)
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { b in
            b.storeBytes(of: window.pid, toByteOffset: 0, as: pid_t.self)
            b.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            b.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self) // "coco"
        }
        for elementID in 0..<maxElementID {
            if elementID % 64 == 0, Date() > deadline { break }
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            // Every element inside a window maps to its id too, and some come
            // before the window itself; raising one of those does nothing.
            if windowID(of: element) == window.id, isWindow(element) { return element }
        }
        return nil
    }
}
