import CoreGraphics

/// Pure display geometry, kept free of AppKit so it can be unit-tested.
/// Window bounds from CGWindowList use a top-left origin at the primary display;
/// `NSScreen` frames use a bottom-left origin. The primary display is the first
/// frame in every list passed here (as with `NSScreen.screens`).
enum Displays {
    /// Converts a CGWindowList rectangle to AppKit screen coordinates.
    static func appKitRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the screen frame (AppKit coordinates) that holds most of a
    /// window with CGWindowList `bounds`, or `nil` if it's on no screen.
    static func screenIndex(for bounds: CGRect, in frames: [CGRect]) -> Int? {
        guard let primary = frames.first else { return nil }
        let rect = appKitRect(bounds, primaryHeight: primary.height)
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in frames.enumerated() {
            let overlap = frame.intersection(rect)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }
}
