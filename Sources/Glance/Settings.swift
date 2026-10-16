import AppKit
import Carbon.HIToolbox
import Observation

/// User preferences, persisted in UserDefaults. Defaults reproduce Glance's
/// original behaviour, so a fresh install works the same as before settings
/// existed. Read values at the moment they're needed; `onChange` covers the few
/// settings that must be applied eagerly (shortcut, menu bar icon).
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    enum Shortcut: String, CaseIterable, Identifiable {
        case commandTab, optionTab
        var id: String { rawValue }
        var label: String { self == .commandTab ? "⌘ Command + Tab" : "⌥ Option + Tab" }
        var symbol: String { self == .commandTab ? "⌘⇥" : "⌥⇥" }
        var modifierSymbol: String { self == .commandTab ? "⌘" : "⌥" }
        /// The same-app window switcher: the shortcut's modifier plus the key above ⇥.
        var appWindowsSymbol: String { modifierSymbol + "`" }
        var eventFlag: CGEventFlags { self == .commandTab ? .maskCommand : .maskAlternate }
        var carbonModifier: Int { self == .commandTab ? cmdKey : optionKey }
    }

    enum SpacesScope: String, CaseIterable, Identifiable {
        case all, current
        var id: String { rawValue }
        var label: String { self == .all ? "All Spaces" : "Current Space only" }
    }

    /// Which display the switcher panel appears on.
    enum PanelDisplay: String, CaseIterable, Identifiable {
        case pointer, activeWindow
        var id: String { rawValue }
        var label: String { self == .pointer ? "Pointer's display" : "Active window's display" }
        var symbol: String { self == .pointer ? "cursorarrow" : "macwindow" }
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max"
            case .dark: "moon"
            }
        }
        /// `nil` follows the system appearance.
        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    enum DisplayStyle: String, CaseIterable, Identifiable {
        case thumbnails, icons
        var id: String { rawValue }
        var label: String { self == .thumbnails ? "Thumbnails" : "App icons" }
    }

    enum ThumbnailSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// Thumbnail width before the layout shrinks it to fit many windows.
        var width: CGFloat {
            switch self {
            case .small: 176
            case .medium: 232
            case .large: 300
            }
        }
        /// Tile content width in icon mode; the icon is about 60% of it.
        var iconTileWidth: CGFloat {
            switch self {
            case .small: 88
            case .medium: 104
            case .large: 128
            }
        }
    }

    enum Change { case shortcut, menuBarIcon, theme }

    @ObservationIgnored var onChange: ((Change) -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var shortcut: Shortcut {
        didSet { save(shortcut.rawValue, "shortcut"); onChange?(.shortcut) }
    }
    var showMenuBarIcon: Bool {
        didSet { save(showMenuBarIcon, "showMenuBarIcon"); onChange?(.menuBarIcon) }
    }
    /// Modifier + ` opens the switcher with only the frontmost app's windows.
    var appWindowsShortcut: Bool {
        didSet { save(appWindowsShortcut, "appWindowsShortcut"); onChange?(.shortcut) }
    }
    var spacesScope: SpacesScope {
        didSet { save(spacesScope.rawValue, "spacesScope") }
    }
    var panelDisplay: PanelDisplay {
        didSet { save(panelDisplay.rawValue, "panelDisplay") }
    }
    /// List only windows on the display the panel appears on.
    var currentDisplayOnly: Bool {
        didSet { save(currentDisplayOnly, "currentDisplayOnly") }
    }
    /// Delay before the panel appears, in milliseconds. A quick tap within this
    /// window switches without drawing anything.
    var showDelayMs: Double {
        didSet { save(showDelayMs, "showDelayMs") }
    }
    var theme: Theme {
        didSet { save(theme.rawValue, "theme"); onChange?(.theme) }
    }
    var displayStyle: DisplayStyle {
        didSet { save(displayStyle.rawValue, "displayStyle") }
    }
    var thumbnailSize: ThumbnailSize {
        didSet { save(thumbnailSize.rawValue, "thumbnailSize") }
    }
    var showTitles: Bool {
        didSet { save(showTitles, "showTitles") }
    }
    /// Look for a newer release on GitHub at most once a day.
    var checkForUpdates: Bool {
        didSet { save(checkForUpdates, "checkForUpdates") }
    }
    /// Bundle identifiers of apps that never appear in the switcher.
    var excludedBundleIDs: [String] {
        didSet { save(excludedBundleIDs, "excludedBundleIDs") }
    }

    static let showDelayRange: ClosedRange<Double> = 0...300

    private init() {
        let d = UserDefaults.standard
        shortcut = d.string(forKey: "shortcut").flatMap(Shortcut.init) ?? .commandTab
        showMenuBarIcon = d.object(forKey: "showMenuBarIcon") as? Bool ?? true
        appWindowsShortcut = d.object(forKey: "appWindowsShortcut") as? Bool ?? false
        spacesScope = d.string(forKey: "spacesScope").flatMap(SpacesScope.init) ?? .all
        panelDisplay = d.string(forKey: "panelDisplay").flatMap(PanelDisplay.init) ?? .pointer
        currentDisplayOnly = d.object(forKey: "currentDisplayOnly") as? Bool ?? false
        let delay = d.object(forKey: "showDelayMs") as? Double ?? 70
        showDelayMs = min(max(delay, Self.showDelayRange.lowerBound), Self.showDelayRange.upperBound)
        theme = d.string(forKey: "theme").flatMap(Theme.init) ?? .system
        displayStyle = d.string(forKey: "displayStyle").flatMap(DisplayStyle.init) ?? .thumbnails
        thumbnailSize = d.string(forKey: "thumbnailSize").flatMap(ThumbnailSize.init) ?? .medium
        showTitles = d.object(forKey: "showTitles") as? Bool ?? true
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? []
        checkForUpdates = d.object(forKey: "checkForUpdates") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
