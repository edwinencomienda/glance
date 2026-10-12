import AppKit
import SwiftUI

/// Borderless, non-activating panel. It never takes focus — keyboard input comes
/// from the event tap — so the app you're switching from stays active.
///
/// The system window shadow is off: it hugs the edge of a masked borderless
/// window and leaves a hard dark rim. Instead the window is larger than the
/// visible panel by `shadowMargin` on every side, and `PanelChrome` draws a soft
/// shadow into that margin. Blur mask, hairline and shadow share one path, so
/// every layer follows exactly the same curve. Material and colours follow the
/// system light/dark appearance.
final class SwitcherPanel: NSPanel {
    static let cornerRadius: CGFloat = 22
    static let shadowRadius: CGFloat = 14
    static let shadowOffsetY: CGFloat = 5
    /// Transparent room around the panel for the shadow to fall into. Derived from
    /// the shadow so its blur (which reaches about 2 × radius, plus the offset)
    /// always fades out fully before the window edge instead of being clipped.
    static let shadowMargin: CGFloat = (shadowRadius * 2 + shadowOffsetY + 6).rounded(.up)

    private let chrome = PanelChrome()
    private let mouse = MouseCatcher()

    init(model: SwitcherModel,
         onHover: @escaping (CGPoint) -> Void,
         onClick: @escaping (CGPoint) -> Void,
         onDragHover: @escaping (CGPoint?) -> Void) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let hosting = NSHostingView(rootView: SwitcherView(model: model))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        chrome.content.addSubview(hosting)

        mouse.onMove = onHover
        mouse.onClick = onClick
        mouse.onDragHover = onDragHover
        mouse.autoresizingMask = [.width, .height]
        chrome.content.addSubview(mouse)

        let root = NSView()
        root.addSubview(chrome)
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The visible panel's rectangle in screen coordinates.
    private var panelFrame: CGRect { frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin) }

    func show(size: CGSize, on screen: NSScreen) {
        let vf = screen.visibleFrame
        let m = Self.shadowMargin
        let origin = CGPoint(x: (vf.midX - size.width / 2).rounded() - m,
                             y: (vf.midY - size.height / 2).rounded() - m)
        setFrame(CGRect(origin: origin, size: CGSize(width: size.width + 2 * m, height: size.height + 2 * m)),
                 display: false)
        chrome.frame = CGRect(x: m, y: m, width: size.width, height: size.height)
        alphaValue = 1
        orderFrontRegardless()
    }

    /// Converts a screen point to the panel content's top-left-origin coordinates.
    func contentPoint(fromScreen point: CGPoint) -> CGPoint? {
        let panel = panelFrame
        guard isVisible, panel.contains(point) else { return nil }
        return CGPoint(x: point.x - panel.minX, y: panel.maxY - point.y)
    }
}

/// The visible panel: soft shadow, blurred material clipped to a continuous
/// rounded rect, and an appearance-aware hairline, all from the same path.
private final class PanelChrome: NSView {
    /// Where the switcher's content goes (clipped to the rounded shape).
    let content: NSVisualEffectView = {
        let effect = NSVisualEffectView()
        effect.material = .popover          // adapts to light and dark mode
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = SwitcherPanel.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        return effect
    }()

    private let shadowLayer = CALayer()
    private let hairline = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(shadowLayer)
        addSubview(content)
        // Above the content so it frames thumbnails too.
        content.layer?.addSublayer(hairline)
        hairline.fillColor = nil
        hairline.lineWidth = 1
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        content.frame = bounds
        let path = Self.continuousPath(bounds, radius: SwitcherPanel.cornerRadius)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = path
        // Inset by half the line width so the 1 pt stroke sits fully inside the
        // clip on whole pixels instead of being cut in half by it.
        hairline.frame = bounds
        hairline.path = Self.continuousPath(bounds.insetBy(dx: 0.5, dy: 0.5),
                                            radius: SwitcherPanel.cornerRadius - 0.5)
        CATransaction.commit()
    }

    /// The same continuous ("squircle") curve as the layer's `.continuous` corners.
    private static func continuousPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Subtle lift: soft, slightly below, lighter in light mode.
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = dark ? 0.3 : 0.14
        shadowLayer.shadowRadius = SwitcherPanel.shadowRadius
        shadowLayer.shadowOffset = CGSize(width: 0, height: -SwitcherPanel.shadowOffsetY)
        hairline.strokeColor = (dark ? NSColor.white.withAlphaComponent(0.14)
                                     : NSColor.black.withAlphaComponent(0.10)).cgColor
        CATransaction.commit()
    }
}

/// Transparent overlay that turns raw mouse input into hover/click callbacks.
/// Uses an always-active tracking area since the panel is never key. It's also a
/// drag destination, so an item dragged over a tile reports where it hovers
/// (`nil` when it leaves). It never accepts the drop itself.
private final class MouseCatcher: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onDragHover: ((CGPoint?) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png, .pdf, .rtf, .html]
                                + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragHover?(convert(sender.draggingLocation, from: nil))
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragHover?(convert(sender.draggingLocation, from: nil))
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragHover?(nil)
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
    }
}
