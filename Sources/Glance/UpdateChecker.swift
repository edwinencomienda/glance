import AppKit
import Observation

/// A release version, `MAJOR.MINOR.PATCH` with an optional leading "v" (as in tags).
struct AppVersion: Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? string.dropFirst() : Substring(string)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part in
            part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) ? Int(part) : nil
        }
        guard numbers.count == 3 else { return nil }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

/// Checks GitHub for a newer release. It only reads the latest release's tag and
/// never downloads or installs anything: "Download" opens the release page, where
/// the notarized DMG lives. Automatic checks run at most once a day, and only when
/// something already happens (launch, opening the menu or Settings), so there are
/// no timers at idle and nothing touches the ⌘⇥ path.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State {
        case idle, checking, upToDate
        case available(AppVersion)
        case failed
    }

    private(set) var state: State = .idle

    static let currentVersion = AppVersion(
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? AppVersion("0.0.0")!

    @ObservationIgnored private let repo = "edwinencomienda/glance"
    @ObservationIgnored private let interval: TimeInterval = 24 * 60 * 60
    @ObservationIgnored private let lastCheckKey = "lastUpdateCheck"

    private init() {}

    var availableVersion: AppVersion? {
        if case .available(let version) = state { version } else { nil }
    }

    /// Release page for a version; built from the parsed version, not from the API response.
    func releasePage(for version: AppVersion) -> URL {
        URL(string: "https://github.com/\(repo)/releases/tag/v\(version)")!
    }

    /// Checks if automatic checks are on and the last check is more than a day old.
    func checkIfDue() {
        guard Settings.shared.checkForUpdates else { return }
        if case .checking = state { return }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval else { return }
        Task { await check() }
    }

    /// "Check for Updates…": checks now and reports the result in an alert.
    func checkNowAndReport() {
        Task {
            await check()
            showResultAlert()
        }
    }

    /// Checks now; the result lands in `state`.
    func check() async {
        if case .checking = state { return }
        state = .checking
        do {
            let latest = try await fetchLatestVersion()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            state = latest > Self.currentVersion ? .available(latest) : .upToDate
        } catch {
            NSLog("Glance: update check failed: \(error.localizedDescription)")
            state = .failed
        }
    }

    private func fetchLatestVersion() async throws -> AppVersion {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Glance/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        // Ephemeral: no cookies, cache or credentials stored.
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Release: Decodable { let tag_name: String }
        guard let version = AppVersion(try JSONDecoder().decode(Release.self, from: data).tag_name) else {
            throw URLError(.cannotParseResponse)
        }
        return version
    }

    private func showResultAlert() {
        let alert = NSAlert()
        switch state {
        case .available(let version):
            alert.messageText = "Glance \(version) is available"
            alert.informativeText = "You have \(Self.currentVersion). Download the new version from GitHub, "
                + "then drag it to Applications to replace this one."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
        case .upToDate:
            alert.messageText = "Glance is up to date"
            alert.informativeText = "\(Self.currentVersion) is the latest version."
        default:
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "Check your internet connection and try again."
        }
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let version = availableVersion {
            NSWorkspace.shared.open(releasePage(for: version))
        }
    }
}

extension UpdateChecker.State {
    var isChecking: Bool { if case .checking = self { true } else { false } }
}
