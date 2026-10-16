import ScreenCaptureKit

/// Captures small window thumbnails with ScreenCaptureKit.
/// Thumbnails are cached per window so the switcher opens instantly with the
/// previous frame, then swaps in fresh captures as they arrive (all in parallel).
@MainActor
final class ThumbnailService {
    private var cache: [CGWindowID: CGImage] = [:]
    private var task: Task<Void, Never>?

    func cached(for windows: [WindowInfo]) -> [CGWindowID: CGImage] {
        var out: [CGWindowID: CGImage] = [:]
        for w in windows { if let img = cache[w.id] { out[w.id] = img } }
        return out
    }

    /// Captures `windows` (the ones this switcher shows). `live` is every window
    /// that still exists: thumbnails of other windows are dropped, but ones that are
    /// merely filtered out of this switcher (same-app, one display) are kept.
    func refresh(_ windows: [WindowInfo], live: Set<CGWindowID>, maxSize: CGSize, scale: CGFloat,
                 onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void) {
        task?.cancel()
        cache = Self.pruned(cache, keeping: live)

        task = Task { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
                  !Task.isCancelled else { return }
            var byID: [CGWindowID: SCWindow] = [:]
            for w in content.windows { byID[w.windowID] = w }

            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for window in windows {
                    guard let scWindow = byID[window.id] else { continue }
                    let config = Self.configuration(for: window.bounds.size, maxSize: maxSize, scale: scale)
                    group.addTask {
                        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                        let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        return (window.id, image)
                    }
                }
                for await (id, image) in group {
                    guard let image, !Task.isCancelled else { continue }
                    self?.cache[id] = image
                    onImage(id, image)
                }
            }
        }
    }

    /// Keeps only the entries of windows in `live`.
    nonisolated static func pruned<Value>(_ cache: [CGWindowID: Value],
                                          keeping live: Set<CGWindowID>) -> [CGWindowID: Value] {
        cache.filter { live.contains($0.key) }
    }

    /// Capture at exactly the pixel size we display — no wasted GPU work or memory.
    private nonisolated static func configuration(for size: CGSize, maxSize: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let fit = min(maxSize.width / max(size.width, 1), maxSize.height / max(size.height, 1), 1)
        let config = SCStreamConfiguration()
        config.width = max(Int(size.width * fit * scale), 1)
        config.height = max(Int(size.height * fit * scale), 1)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.capturesAudio = false
        return config
    }
}
