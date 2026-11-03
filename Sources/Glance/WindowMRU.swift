import AppKit

/// Most-recently-used ordering across Spaces. Windows on other Spaces never
/// appear in the current Space's z-order, so we remember when each window was
/// last frontmost. Updated only on app activation and on our own switches; no
/// polling.
@MainActor
final class WindowMRU {
    private var stamps: [CGWindowID: UInt64] = [:]
    /// When each app was last active, for ordering app tiles (apps with no
    /// listed window). Kept apart from `stamps`, which drops ids that aren't
    /// listed: an app's tile only shows up once its windows are gone.
    private var appStamps: [pid_t: UInt64] = [:]
    private var clock: UInt64 = 0
    private var observer: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.touchApp(pid)
                if let id = WindowList.frontmostWindow(of: pid) { self?.touch(id) }
            }
        }
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { _ = self?.appStamps.removeValue(forKey: pid) }
        }
    }

    func touch(_ id: CGWindowID) {
        clock += 1
        stamps[id] = clock
    }

    func touchApp(_ pid: pid_t) {
        clock += 1
        appStamps[pid] = clock
    }

    /// Records a switch to `item`: a window, or an app tile.
    func touch(_ item: WindowInfo) {
        item.isApp ? touchApp(item.pid) : touch(item.id)
    }

    /// Orders `current` (visible Spaces, front-to-back z-order), `others`
    /// (other Spaces, window-server order) and app tiles into one MRU list.
    func order(current: [WindowInfo], others: [WindowInfo], apps: [WindowInfo] = []) -> [WindowInfo] {
        // The front window on screen is, by definition, the most recent.
        if let front = current.first { touch(front.id) }
        let live = Set((current + others).map(\.id))
        stamps = stamps.filter { live.contains($0.key) }

        // Stable sort by recency; unseen windows keep their base order at the end.
        let base = current + others + apps
        let stamp = { (w: WindowInfo) in (w.isApp ? self.appStamps[w.pid] : self.stamps[w.id]) ?? 0 }
        let sorted = base.enumerated().sorted { a, b in
            let sa = stamp(a.element), sb = stamp(b.element)
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)

        // Within visible Spaces the z-order is authoritative (it also catches window
        // changes inside one app that we never see), so refill the slots held by
        // current-Space windows in z-order.
        let currentIDs = Set(current.map(\.id))
        var next = current.makeIterator()
        return sorted.map { currentIDs.contains($0.id) ? next.next()! : $0 }
    }
}
