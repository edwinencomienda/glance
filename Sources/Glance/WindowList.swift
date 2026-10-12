import AppKit

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let bounds: CGRect
    let icon: NSImage?

    static func == (a: WindowInfo, b: WindowInfo) -> Bool { a.id == b.id && a.title == b.title }
}

enum WindowList {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    private static var iconCache: [pid_t: NSImage] = [:]

    /// On-screen windows of the current Space, front-to-back (most recently used first).
    /// Uses CGWindowList only — a single cheap WindowServer call, no per-app IPC.
    static func current() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        var apps: [pid_t: NSRunningApplication?] = [:]
        var result: [WindowInfo] = []
        result.reserveCapacity(16)

        for info in raw {
            guard (info[kCGWindowLayer] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber] as? CGWindowID,
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0.01,
                  let boundsDict = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 80, bounds.height >= 60
            else { continue }

            let app: NSRunningApplication?
            if let cached = apps[pid] { app = cached } else {
                app = NSRunningApplication(processIdentifier: pid)
                apps[pid] = app
            }
            guard let app, app.activationPolicy == .regular else { continue }

            let appName = app.localizedName ?? (info[kCGWindowOwnerName] as? String) ?? ""
            let title = (info[kCGWindowName] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName

            result.append(WindowInfo(
                id: id, pid: pid, title: title, appName: appName,
                bounds: bounds, icon: icon(for: app)
            ))
        }
        return result
    }

    private static func icon(for app: NSRunningApplication) -> NSImage? {
        if let cached = iconCache[app.processIdentifier] { return cached }
        let icon = app.icon
        iconCache[app.processIdentifier] = icon
        return icon
    }
}
