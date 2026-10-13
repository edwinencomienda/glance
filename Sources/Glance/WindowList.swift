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
    private static var iconCache: [pid_t: NSImage] = [:]

    /// Switchable windows on every Space, as two lists: windows on the visible
    /// Spaces (front-to-back z-order) and windows on other Spaces, including
    /// full-screen ones. Two CGWindowList calls plus a cheap Space lookup per
    /// candidate; no per-app Accessibility IPC.
    static func current(includeOtherSpaces: Bool = true,
                        excluding excluded: Set<String> = []) -> (current: [WindowInfo], others: [WindowInfo]) {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return ([], []) }

        // `.optionAll` finds windows on every Space but returns them in a fixed
        // order, not z-order. The on-screen list is front-to-back, so use it to
        // rank windows on the visible Spaces.
        var zIndex: [CGWindowID: Int] = [:]
        if let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[CFString: Any]] {
            for (index, info) in onScreen.enumerated() {
                if let id = info[kCGWindowNumber] as? CGWindowID { zIndex[id] = index }
            }
        }

        let spaceLayout = Spaces.layout()
        // One lookup table instead of an NSRunningApplication per window owner.
        var apps: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let bundleID = app.bundleIdentifier, excluded.contains(bundleID) { continue }
            apps[app.processIdentifier] = app
        }
        var current: [WindowInfo] = [], others: [WindowInfo] = []
        // Windows on full-screen Spaces, keyed by Space, for the overlay filter below.
        var fullScreenSpaceOf: [CGWindowID: UInt64] = [:]
        // Titled window frames per app, and untitled windows, for the popup filter below.
        var titledFrames: [pid_t: [CGRect]] = [:]
        var untitled: Set<CGWindowID> = []

        for info in raw {
            guard (info[kCGWindowLayer] as? Int) == 0,
                  // Glance's own windows count too (Settings, while it's open and
                  // Glance is a regular app); the switcher panel isn't layer 0.
                  let pid = info[kCGWindowOwnerPID] as? pid_t,
                  let app = apps[pid],
                  let id = info[kCGWindowNumber] as? CGWindowID,
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0.01,
                  let boundsDict = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            let windowName = (info[kCGWindowName] as? String).flatMap { $0.isEmpty ? nil : $0 }
            guard Self.isSwitchableSize(bounds.size, titled: windowName != nil) else { continue }

            let onScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
            let isCurrent: Bool
            if let spaceLayout, let spaces = Spaces.of(id) {
                // No Space: helper, minimized or inactive-tab window.
                guard !spaces.isEmpty else { continue }
                isCurrent = !spaceLayout.visible.isDisjoint(with: spaces)
                if !isCurrent && !includeOtherSpaces { continue }
                if let fullScreen = spaces.first(where: spaceLayout.fullScreen.contains) {
                    fullScreenSpaceOf[id] = fullScreen
                }
                // On a visible Space but not drawn: hidden helper window.
                if isCurrent && !onScreen { continue }
            } else {
                // Space lookup unavailable: current Space only.
                guard onScreen else { continue }
                isCurrent = true
            }

            let appName = app.localizedName ?? (info[kCGWindowOwnerName] as? String) ?? ""
            if windowName == nil { untitled.insert(id) } else { titledFrames[pid, default: []].append(bounds) }
            let title = windowName ?? appName
            let window = WindowInfo(id: id, pid: pid, title: title, appName: appName,
                                    bounds: bounds, icon: icon(for: app))
            if isCurrent { current.append(window) } else { others.append(window) }
        }

        // A full-screen Space holds the app's window(s) plus overlays such as the
        // toolbar strip that slides down from the top edge (a full-width, ~100 pt
        // tall, untitled window). Real windows there fill the height (also in
        // Split View), so drop anything under half the tallest one.
        if !fullScreenSpaceOf.isEmpty {
            var tallest: [UInt64: CGFloat] = [:]
            for w in current + others {
                if let space = fullScreenSpaceOf[w.id] { tallest[space] = max(tallest[space] ?? 0, w.bounds.height) }
            }
            let isOverlay = { (w: WindowInfo) -> Bool in
                guard let space = fullScreenSpaceOf[w.id], let top = tallest[space] else { return false }
                return w.bounds.height < top * 0.5
            }
            current.removeAll(where: isOverlay)
            others.removeAll(where: isOverlay)
        }

        // Browser popups (address-bar suggestions, menus, extension bubbles) are
        // untitled layer-0 windows drawn over the browser window.
        if !untitled.isEmpty {
            let isPopup = { (w: WindowInfo) -> Bool in
                untitled.contains(w.id) && Self.isPopup(w.bounds, over: titledFrames[w.pid] ?? [])
            }
            current.removeAll(where: isPopup)
            others.removeAll(where: isPopup)
        }

        current.sort { (zIndex[$0.id] ?? .max) < (zIndex[$1.id] ?? .max) }
        return (current, others)
    }

    /// Untitled windows under 100×100 are helpers and strips. A title marks a real
    /// window, so short ones such as Finder's progress window (404×88) stay.
    static func isSwitchableSize(_ size: CGSize, titled: Bool) -> Bool {
        let minSide: CGFloat = titled ? 50 : 100
        return size.width >= minSide && size.height >= minSide
    }

    /// Whether an untitled window at `frame` is a popup of one of the app's titled
    /// windows: it overlaps one that is larger than itself. Untitled windows that
    /// stand alone, or are the app's main window, stay in the list.
    static func isPopup(_ frame: CGRect, over titledFrames: [CGRect]) -> Bool {
        titledFrames.contains { parent in
            parent.intersects(frame) && parent.width * parent.height > frame.width * frame.height
        }
    }

    /// The front-most on-screen window of an app, if any.
    static func frontmostWindow(of pid: pid_t) -> CGWindowID? {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }
        for info in raw where (info[kCGWindowLayer] as? Int) == 0 && (info[kCGWindowOwnerPID] as? pid_t) == pid {
            if let id = info[kCGWindowNumber] as? CGWindowID { return id }
        }
        return nil
    }

    private static func icon(for app: NSRunningApplication) -> NSImage? {
        if let cached = iconCache[app.processIdentifier] { return cached }
        let icon = app.icon
        iconCache[app.processIdentifier] = icon
        return icon
    }
}
