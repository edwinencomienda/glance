import AppKit

/// Read-only Mission Control Space lookups via SkyLight. Every call returns `nil`
/// when the private symbols are unavailable, so callers can fall back to the
/// current Space only.
enum Spaces {
    private static let allSpacesMask: Int32 = 0x7

    private static let connection: Int32? = SkyLight.mainConnection.map { $0() }

    private static let fullScreenType = 4

    struct Layout {
        /// The Space currently shown on each display.
        var visible: Set<UInt64> = []
        /// Spaces created by full-screen (or Split View) apps.
        var fullScreen: Set<UInt64> = []
    }

    static func layout() -> Layout? {
        guard let connection, let copy = SkyLight.copyManagedDisplaySpaces,
              let displays = copy(connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        var layout = Layout()
        for display in displays {
            if let current = display["Current Space"] as? [String: Any],
               let id = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value {
                layout.visible.insert(id)
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                if (space["type"] as? NSNumber)?.intValue == fullScreenType,
                   let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value {
                    layout.fullScreen.insert(id)
                }
            }
        }
        return layout.visible.isEmpty ? nil : layout
    }

    /// Spaces a window belongs to. Empty for helper windows, minimized windows
    /// and inactive native tabs; `nil` if the lookup is unavailable.
    static func of(_ window: CGWindowID) -> [UInt64]? {
        guard let connection, let copy = SkyLight.copySpacesForWindows,
              let spaces = copy(connection, allSpacesMask, [window] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return spaces.map(\.uint64Value)
    }
}
