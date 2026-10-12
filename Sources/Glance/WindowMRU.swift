import AppKit

/// Most-recently-used ordering across Spaces. Windows on other Spaces never
/// appear in the current Space's z-order, so we remember when each window was
/// last frontmost. Updated only on app activation and on our own switches; no
/// polling.
@MainActor
final class WindowMRU {
    private var stamps: [CGWindowID: UInt64] = [:]
    private var clock: UInt64 = 0
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                if let id = WindowList.frontmostWindow(of: pid) { self?.touch(id) }
            }
        }
    }

    func touch(_ id: CGWindowID) {
        clock += 1
        stamps[id] = clock
    }

    /// Orders `current` (visible Spaces, front-to-back z-order) and `others`
    /// (other Spaces, window-server order) into one MRU list.
    func order(current: [WindowInfo], others: [WindowInfo]) -> [WindowInfo] {
        // The front window on screen is, by definition, the most recent.
        if let front = current.first { touch(front.id) }
        let live = Set((current + others).map(\.id))
        stamps = stamps.filter { live.contains($0.key) }

        // Stable sort by recency; unseen windows keep their base order at the end.
        let base = current + others
        let sorted = base.enumerated().sorted { a, b in
            let sa = stamps[a.element.id] ?? 0, sb = stamps[b.element.id] ?? 0
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
