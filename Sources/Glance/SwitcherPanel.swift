import AppKit
import SwiftUI

/// Borderless, non-activating HUD panel. It never takes focus — keyboard input
/// comes from the event tap — so the app you're switching from stays active.
final class SwitcherPanel: NSPanel {
    static let cornerRadius: CGFloat = 24

    private let effect = NSVisualEffectView()
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
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: SwitcherView(model: model))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        // Hairline border for definition against busy wallpapers.
        let border = NSView()
        border.wantsLayer = true
        border.layer?.cornerRadius = Self.cornerRadius
        border.layer?.cornerCurve = .continuous
        border.layer?.borderWidth = 1
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        border.autoresizingMask = [.width, .height]
        effect.addSubview(border)

        mouse.onMove = onHover
        mouse.onClick = onClick
        mouse.onDragHover = onDragHover
        mouse.autoresizingMask = [.width, .height]
        effect.addSubview(mouse)

        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(size: CGSize, on screen: NSScreen) {
        let vf = screen.visibleFrame
        let origin = CGPoint(x: (vf.midX - size.width / 2).rounded(), y: (vf.midY - size.height / 2).rounded())
        setFrame(CGRect(origin: origin, size: size), display: false)
        alphaValue = 1
        orderFrontRegardless()
        invalidateShadow()
    }

    /// Converts a screen point to the content's top-left-origin coordinates.
    func contentPoint(fromScreen point: CGPoint) -> CGPoint? {
        guard isVisible, frame.contains(point) else { return nil }
        return CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
