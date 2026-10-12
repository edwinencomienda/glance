import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Owns the Settings window. The window (with its 1 s status refresh and the
/// mascot's blinking) only exists while it's open, so Settings costs nothing at idle.
/// While it's open Glance becomes a regular app, so the window shows up in the
/// Dock, in ⌘⇥ (Glance's and the system's) and gets a standard menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Glance Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // Become a regular app first; activating in the same turn as the policy
        // change is often declined. Deferring also gets past the status-item menu's
        // tracking loop, and orderFrontRegardless guarantees the window appears even
        // if cooperative activation is declined.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            // Don't auto-focus the first control (its focus ring looks like a glitch);
            // Tab still moves focus for keyboard users.
            window.makeFirstResponder(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Back to a menu bar-only app: no Dock icon, not in ⌘⇥.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Colours from the app icon (Resources/AppIcon.icon).
enum Brand {
    static let blue = Color(red: 0.071, green: 0.345, blue: 0.910)   // #1258E8 background
    static let mid = Color(red: 0.157, green: 0.467, blue: 0.929)    // #2877ED front card
    static let light = Color(red: 0.251, green: 0.549, blue: 0.961)  // #408CF5 back card
    static let cyan = Color(red: 0.133, green: 0.655, blue: 0.941)   // #22A7F0 side card
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable private var settings = Settings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    @State private var mascotCenter: CGPoint = .zero
    @State private var look: CGSize = .zero

    /// Cards' content is 428 pt wide; 10 pt gaps give whole-point tiles for 2 and 3
    /// across (209 / 136 pt), so edges stay crisp on non-Retina displays.
    private let tileSpacing: CGFloat = 10

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(spacing: 18) {
                    general
                    shortcut
                    switcher
                    appearance
                    excludedApps
                    permissions
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
        }
        .scrollIndicators(.never)
        .ignoresSafeArea(edges: .top)
        .frame(width: 500, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Brand.blue)
        .coordinateSpace(name: "settings")
        .onContinuousHover(coordinateSpace: .named("settings")) { phase in
            switch phase {
            case .active(let point): lookAt(point)
            case .ended: withAnimation(.spring(duration: 0.6)) { look = .zero }
            }
        }
        .onPreferenceChange(MascotCenterKey.self) { mascotCenter = $0 }
        .onReceive(refresh) { _ in refreshStatus() }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Brand.blue
            // The icon's tilted window cards, faint, framing the mascot.
            WindowCard(color: Brand.light, size: CGSize(width: 140, height: 108), angle: -8)
                .offset(x: -150, y: 8).opacity(0.55)
            WindowCard(color: Brand.cyan, size: CGSize(width: 130, height: 100), angle: 8)
                .offset(x: 160, y: 22).opacity(0.5)
            WindowCard(color: Brand.mid, size: CGSize(width: 160, height: 118), angle: -8)
                .offset(x: 0, y: 40).opacity(0.6)

            VStack(spacing: 10) {
                GlanceMascot(look: look, reduceMotion: reduceMotion)
                    .frame(width: 108)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: MascotCenterKey.self,
                                               value: proxy.frame(in: .named("settings")).center)
                    })
                VStack(spacing: 2) {
                    Text("Glance")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Every window, one glance away")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
            }
            .padding(.top, 26)
        }
        .frame(height: 166)
        .clipped()
    }

    // MARK: Sections

    private var general: some View {
        SettingsCard("General", symbol: "gearshape") {
            ToggleRow("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if loginNeedsApproval {
                Note("Approve Glance in System Settings › General › Login Items.")
            }
            Divider()
            ToggleRow("Show icon in menu bar", isOn: $settings.showMenuBarIcon)
            if !settings.showMenuBarIcon {
                Note("To open Settings again, launch Glance from Spotlight or Finder.")
            }
        }
    }

    private var shortcut: some View {
        SettingsCard("Shortcut", symbol: "command") {
            HStack(spacing: tileSpacing) {
                ForEach(Settings.Shortcut.allCases) { option in
                    ChoiceTile(selected: settings.shortcut == option) {
                        settings.shortcut = option
                    } content: {
                        VStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Keycap(option == .commandTab ? "⌘" : "⌥")
                                Keycap("⇥", wide: true)
                            }
                            Text(option == .commandTab ? "Replaces the macOS switcher" : "Keeps the macOS switcher")
                                .font(.system(size: 11))
                                .opacity(settings.shortcut == option ? 0.85 : 0.6)
                        }
                    }
                }
            }
        }
    }

    private var switcher: some View {
        SettingsCard("Switcher", symbol: "rectangle.on.rectangle") {
            HStack(spacing: tileSpacing) {
                ForEach(Settings.SpacesScope.allCases) { scope in
                    ChoiceTile(selected: settings.spacesScope == scope, compact: true) {
                        settings.spacesScope = scope
                    } content: {
                        Label(scope == .all ? "All Spaces" : "Current Space",
                              systemImage: scope == .all ? "square.stack.3d.up" : "square")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            Divider()
            HStack {
                Text("Panel delay")
                Spacer()
                // Snap to 10 ms without `step:`, which draws a tick per step.
                Slider(value: Binding(get: { settings.showDelayMs },
                                      set: { settings.showDelayMs = ($0 / 10).rounded() * 10 }),
                       in: Settings.showDelayRange)
                    .frame(width: 170)
                Text("\(Int(settings.showDelayMs)) ms")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    // Brand blue is too dark to read on the dark-mode background.
                    .foregroundStyle(colorScheme == .dark ? Brand.light : Brand.blue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Brand.blue.opacity(colorScheme == .dark ? 0.25 : 0.12), in: Capsule())
                    .frame(width: 62, alignment: .trailing)
            }
            Note("A quick \(settings.shortcut.symbol) within the delay switches instantly, no panel.")
        }
    }

    private var appearance: some View {
        SettingsCard("Appearance", symbol: "paintbrush") {
            HStack(spacing: tileSpacing) {
                ForEach(Settings.DisplayStyle.allCases) { style in
                    ChoiceTile(selected: settings.displayStyle == style, compact: true) {
                        settings.displayStyle = style
                    } content: {
                        HStack(spacing: 10) {
                            Group {
                                if style == .thumbnails { ThumbnailGlyph(scale: 0.75) } else { IconGlyph(size: 22) }
                            }
                            .frame(width: 34, height: 26)
                            Text(style.label).font(.system(size: 12, weight: .medium))
                        }
                    }
                }
            }
            HStack(spacing: tileSpacing) {
                ForEach(Settings.ThumbnailSize.allCases) { size in
                    let scale: CGFloat = size == .small ? 0.7 : size == .medium ? 0.85 : 1
                    ChoiceTile(selected: settings.thumbnailSize == size, compact: true) {
                        settings.thumbnailSize = size
                    } content: {
                        VStack(spacing: 8) {
                            Group {
                                if settings.displayStyle == .icons {
                                    IconGlyph(size: 26 * scale)
                                } else {
                                    ThumbnailGlyph(scale: scale)
                                }
                            }
                            .frame(height: 30)
                            Text(size.label).font(.system(size: 11, weight: .medium))
                        }
                    }
                }
            }
            Divider()
            ToggleRow("Show window titles", isOn: $settings.showTitles)
            if settings.displayStyle == .icons && !settings.showTitles {
                Note("With app icons, titles tell apart windows of the same app.")
            }
        }
    }

    private var excludedApps: some View {
        SettingsCard("Excluded Apps", symbol: "eye.slash") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    AppChip(bundleID: bundleID) {
                        withAnimation(.snappy) { settings.excludedBundleIDs.removeAll { $0 == bundleID } }
                    }
                }
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") { exclude(app.bundleIdentifier) }
                    }
                    if !runningApps.isEmpty { Divider() }
                    Button("Choose from Applications…", action: chooseApp)
                } label: {
                    Label("Add App", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .foregroundStyle(Brand.blue)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Brand.blue.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            Note(settings.excludedBundleIDs.isEmpty
                 ? "Hide apps you never switch to by window."
                 : "Windows of these apps never appear in the switcher.")
        }
    }

    private var permissions: some View {
        SettingsCard("Permissions", symbol: "lock.shield") {
            PermissionRow(title: "Accessibility", detail: "Catch the shortcut and switch windows",
                          granted: accessibilityGranted, pane: "Privacy_Accessibility")
            Divider()
            PermissionRow(title: "Screen Recording", detail: "Window thumbnails and titles",
                          granted: screenRecordingGranted, pane: "Privacy_ScreenCapture")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            GlanceMascot(look: .zero, reduceMotion: true, color: Color.secondary.opacity(0.6))
                .frame(width: 26)
            Text("Glance \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    // MARK: Behaviour

    /// Points the mascot's eyes toward the cursor; closer means a bigger glance.
    private func lookAt(_ point: CGPoint) {
        let dx = point.x - mascotCenter.x, dy = point.y - mascotCenter.y
        let distance = max(hypot(dx, dy), 1)
        let strength = min(distance / 220, 1)
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
            look = CGSize(width: dx / distance * strength, height: dy / distance * strength)
        }
    }

    /// Regular running apps that aren't excluded yet, sorted by name.
    private var runningApps: [NSRunningApplication] {
        let excluded = Set(settings.excludedBundleIDs)
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return id != own && !excluded.contains(id)
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func exclude(_ bundleID: String?) {
        guard let bundleID, !settings.excludedBundleIDs.contains(bundleID) else { return }
        withAnimation(.snappy) { settings.excludedBundleIDs.append(bundleID) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { exclude(Bundle(url: url)?.bundleIdentifier) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Glance: launch-at-login change failed: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    private func refreshStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        loginNeedsApproval = status == .requiresApproval
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }
}

// MARK: - Mascot

/// The Glance logo as a live character: a dome with two capsule eyes resting on
/// a horizon line. `look` (each axis −1…1) shifts the eyes; it blinks now and then.
/// Geometry follows Resources/Logo/glance-logo.svg (art box 384 × 154).
struct GlanceMascot: View {
    var look: CGSize
    var reduceMotion: Bool
    var color: Color = .white
    @State private var blinking = false

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 384
            ZStack(alignment: .topLeading) {
                Dome().fill(color)
                    .frame(width: 280 * s, height: 140 * s)
                    .offset(x: 52 * s, y: 0)
                ForEach([134.0, 222.0], id: \.self) { x in
                    Capsule()
                        .fill(color)
                        .frame(width: 28 * s, height: 52 * s)
                        .scaleEffect(x: 1, y: blinking ? 0.12 : 1, anchor: .center)
                        .offset(x: (x + look.width * 10) * s, y: (68 + look.height * 9) * s)
                }
                Capsule()
                    .fill(color)
                    .frame(width: 384 * s, height: 28 * s)
                    .offset(x: 0, y: 126 * s)
            }
        }
        .aspectRatio(384 / 154, contentMode: .fit)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5.5)))
                withAnimation(.easeIn(duration: 0.07)) { blinking = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeOut(duration: 0.12)) { blinking = false }
            }
        }
    }
}

/// Half ring: outer radius 140, inner 112, flat side down (in a 280 × 140 box).
private struct Dome: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2, inner = r * 112 / 140
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var p = Path()
        p.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: center.x + inner, y: center.y))
        p.addArc(center: center, radius: inner, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        p.closeSubpath()
        return p
    }
}

private struct MascotCenterKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Building blocks

private struct WindowCard: View {
    let color: Color
    let size: CGSize
    let angle: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(color)
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(angle))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5))
        }
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A selectable card. The selected one fills with solid Glance blue (white
/// content); unselected ones are soft neutral tiles. No outlines: thin strokes
/// smear on non-Retina displays, filled shapes stay crisp everywhere.
private struct ChoiceTile<Content: View>: View {
    let selected: Bool
    var compact = false
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(selected ? Color.white : Color.primary)
                .environment(\.onBrandFill, selected)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 10 : 14)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(selected ? Brand.blue : Color.primary.opacity(hovering ? 0.08 : 0.045))
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        // The system focus ring otherwise draws over the first tile's border.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

private struct Keycap: View {
    let symbol: String
    var wide = false
    @Environment(\.onBrandFill) private var onBrandFill
    init(_ symbol: String, wide: Bool = false) {
        self.symbol = symbol
        self.wide = wide
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(onBrandFill ? Brand.blue : Color.primary)
            .frame(width: wide ? 46 : 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(onBrandFill ? Color.white : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(onBrandFill ? 0.3 : 0.18), radius: 0, y: 2)
            )
    }
}

/// Two tilted window cards, like the app icon, at a given scale.
private struct ThumbnailGlyph: View {
    let scale: CGFloat
    @Environment(\.onBrandFill) private var onBrandFill

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * scale, style: .continuous)
                .fill(onBrandFill ? Color.white.opacity(0.45) : Brand.light.opacity(0.6))
                .frame(width: 30 * scale, height: 22 * scale)
                .rotationEffect(.degrees(-8))
                .offset(x: -5 * scale, y: -2 * scale)
            RoundedRectangle(cornerRadius: 4 * scale, style: .continuous)
                .fill(onBrandFill ? Color.white : Brand.blue)
                .frame(width: 30 * scale, height: 22 * scale)
                .rotationEffect(.degrees(6))
                .offset(x: 5 * scale, y: 2 * scale)
        }
    }
}

/// An app-icon tile with the Glance mark, for the "App icons" option.
private struct IconGlyph: View {
    let size: CGFloat
    @Environment(\.onBrandFill) private var onBrandFill

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(onBrandFill ? Color.white : Brand.blue)
            .frame(width: size, height: size)
            .overlay {
                GlanceMascot(look: .zero, reduceMotion: true, color: onBrandFill ? Brand.blue : .white)
                    .frame(width: size * 0.7)
            }
    }
}

/// Excluded app: icon + name, with a remove button.
private struct AppChip: View {
    let bundleID: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 7) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                  ?? NSWorkspace.shared.icon(for: .application))
                .resizable()
                .frame(width: 18, height: 18)
            Text(url.map { FileManager.default.displayName(atPath: $0.path) }?
                    .replacingOccurrences(of: ".app", with: "") ?? bundleID)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(hovering ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background(Color.primary.opacity(hovering ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering = $0 }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let pane: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
            } else {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Grant", systemImage: "arrow.up.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension EnvironmentValues {
    /// True inside a selected `ChoiceTile`, so content can switch to on-blue colours.
    @Entry var onBrandFill = false
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
