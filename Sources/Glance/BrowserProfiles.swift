import AppKit
import ApplicationServices

/// Resolves browser profile labels only after the switcher is shown. Accessibility
/// calls run off the main thread and never delay a quick switch.
@MainActor
final class BrowserProfiles {
    private var task: Task<Void, Never>?
    private var generation = 0
    private var cache: [CGWindowID: (pid: pid_t, name: String)] = [:]

    func cancel() { task?.cancel(); task = nil; generation += 1 }

    func cached(for windows: [WindowInfo], live: Set<CGWindowID>) -> [CGWindowID: String] {
        cache = cache.filter { live.contains($0.key) }
        var result: [CGWindowID: String] = [:]
        for window in windows {
            if let entry = cache[window.id], entry.pid == window.pid { result[window.id] = entry.name }
        }
        return result
    }

    func refresh(_ windows: [WindowInfo], onProfile: @escaping @MainActor (CGWindowID, String?) -> Void) {
        cancel()
        let supported = Set(NSWorkspace.shared.runningApplications.compactMap { app -> pid_t? in
            guard let id = app.bundleIdentifier, Self.browserIDs.contains(id) else { return nil }
            return app.processIdentifier
        })
        let candidates = windows.filter { !$0.isApp && supported.contains($0.pid) }
        let currentGeneration = generation
        task = Task.detached(priority: .utility) { [weak self] in
            for window in candidates {
                guard !Task.isCancelled else { return }
                let name = Self.profile(for: window)
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    guard self.generation == currentGeneration else { return }
                    self.cache[window.id] = name.map { (window.pid, $0) }
                    onProfile(window.id, name)
                }
            }
        }
    }

    private nonisolated static let browserIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary"
    ]
    private nonisolated static let avatarClasses: Set<String> = ["AvatarToolbarButton", "EdgeAvatarToolbarButton"]

    nonisolated static func label(classes: [String], title: String) -> String? {
        guard !avatarClasses.isDisjoint(with: classes) else { return nil }
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Edge adds this accessibility suffix to its profile button label.
        if classes.contains("EdgeAvatarToolbarButton"), name.hasSuffix(" Profile") {
            name = String(name.dropLast(" Profile".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name.isEmpty ? nil : name
    }

    private nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private nonisolated static func profile(for window: WindowInfo) -> String? {
        guard let root = AXWindowResolver.element(for: window) else { return nil }
        let deadline = Date().addingTimeInterval(0.35)
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while let (element, depth) = pending.popLast(), visited < 250, Date() < deadline, !Task.isCancelled {
            visited += 1
            AXUIElementSetMessagingTimeout(element, 0.1)
            if let classes = attribute(element, "AXDOMClassList") as? [String],
               !avatarClasses.isDisjoint(with: classes) {
                return label(classes: classes, title: attribute(element, kAXTitleAttribute) as? String ?? "")
            }
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == "AXWebArea" || role == "AXScrollArea" || role == "AXTabGroup" { continue }
            if depth < 10, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return nil
    }
}
