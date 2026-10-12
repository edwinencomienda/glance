import AppKit

/// The Glance logo (Resources/Logo/glance-logo.svg) drawn as a template image, so
/// it's crisp at any scale and follows the menu bar's light/dark appearance.
/// Paths use the SVG's coordinate space; keep them in sync if the logo changes.
enum MenuBarIcon {
    static func make(size: CGSize = CGSize(width: 28, height: 18)) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.setFill()
            logoPath(fitting: rect).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glance"
        return image
    }

    private static func logoPath(fitting rect: CGRect) -> NSBezierPath {
        // Visible bounds of the artwork in SVG units (after its translate(0 63)).
        let art = CGRect(x: 64, y: 179, width: 384, height: 154)
        let center = CGPoint(x: 256, y: 319)

        let path = NSBezierPath()
        // Head: half ring, outer radius 140, inner 112.
        path.appendArc(withCenter: center, radius: 140, startAngle: 180, endAngle: 0, clockwise: false)
        path.line(to: CGPoint(x: center.x + 112, y: center.y))
        path.appendArc(withCenter: center, radius: 112, startAngle: 0, endAngle: 180, clockwise: true)
        path.close()
        // Eyes and horizon line.
        for r in [CGRect(x: 198, y: 247, width: 28, height: 52),
                  CGRect(x: 286, y: 247, width: 28, height: 52),
                  CGRect(x: 64, y: 305, width: 384, height: 28)] {
            path.append(NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14))
        }

        let scale = min(rect.width / art.width, rect.height / art.height)
        var transform = AffineTransform(scaleByX: scale, byY: scale)
        transform.append(AffineTransform(translationByX: rect.midX - art.midX * scale,
                                         byY: rect.midY - art.midY * scale))
        path.transform(using: transform)
        return path
    }
}
