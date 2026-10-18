import AppKit
import Observation

@Observable
final class SwitcherModel {
    var windows: [WindowInfo] = []
    var thumbnails: [CGWindowID: CGImage] = [:]
    var selected = 0
    var layout = SwitcherLayout.empty
    /// The tile under the pointer, which shows the close (or quit) button.
    var hovered: Int?
    /// The pointer is on the hovered tile's button.
    var buttonHot = false
    /// The quit modifier is held: the button quits the app instead of closing the window.
    var quitMode = false
}

/// What the pointer is over.
enum SwitcherHit: Equatable {
    case tile(Int)
    /// The close / quit button in the tile's top-right corner.
    case button(Int)

    var index: Int {
        switch self { case .tile(let i), .button(let i): i }
    }
}

/// All geometry is computed up front so the panel can be sized and placed in one
/// shot (no SwiftUI layout round-trips), and mouse hit-testing is plain math.
struct SwitcherLayout: Equatable {
    static let padding: CGFloat = 14
    static let spacing: CGFloat = 6
    static let tileInset: CGFloat = 10
    static let defaultTitleHeight: CGFloat = 26

    var thumbSize: CGSize
    /// Height of the title row under each thumbnail; 0 when titles are hidden.
    var titleHeight: CGFloat = defaultTitleHeight
    /// App icons instead of window thumbnails; `thumbSize.height` is the icon size.
    var iconsOnly = false
    var columns: Int
    var rows: Int
    var count: Int

    static let empty = SwitcherLayout(thumbSize: .zero, columns: 1, rows: 0, count: 0)

    var itemSize: CGSize {
        CGSize(width: thumbSize.width + Self.tileInset * 2,
               height: thumbSize.height + Self.tileInset * 2 + titleHeight)
    }

    var panelSize: CGSize {
        let item = itemSize
        return CGSize(
            width: CGFloat(columns) * item.width + CGFloat(columns - 1) * Self.spacing + Self.padding * 2,
            height: CGFloat(rows) * item.height + CGFloat(max(rows - 1, 0)) * Self.spacing + Self.padding * 2
        )
    }

    func itemsInRow(_ row: Int) -> Int { min(columns, count - row * columns) }

    /// Fits `count` tiles into `bounds`, shrinking thumbnails only when needed.
    static func make(count: Int, in bounds: CGSize,
                     thumbWidth: CGFloat = 232, showTitles: Bool = true,
                     iconsOnly: Bool = false) -> SwitcherLayout {
        let maxW = bounds.width * 0.9, maxH = bounds.height * 0.85
        // Thumbnails are 16:10; in icon mode the "thumb" is a square-ish icon area.
        let aspect: CGFloat = iconsOnly ? 0.6 : 0.625
        let minWidth: CGFloat = iconsOnly ? 56 : 96
        var thumbW = thumbWidth
        while true {
            let thumb = CGSize(width: thumbW, height: (thumbW * aspect).rounded())
            var layout = SwitcherLayout(thumbSize: thumb, titleHeight: showTitles ? defaultTitleHeight : 0,
                                        iconsOnly: iconsOnly, columns: 1, rows: 1, count: count)
            let item = layout.itemSize
            let fitCols = Int((maxW - padding * 2 + spacing) / (item.width + spacing))
            let cols = max(1, min(count, fitCols))
            let rows = Int((Double(count) / Double(cols)).rounded(.up))
            // Rebalance so the last row isn't nearly empty.
            layout.columns = Int((Double(count) / Double(rows)).rounded(.up))
            layout.rows = rows
            if layout.panelSize.height <= maxH || thumbW <= minWidth { return layout }
            thumbW = (thumbW * 0.88).rounded()
        }
    }

    static let buttonSize: CGFloat = 20
    /// Distance from the tile's top and right edges to the button.
    static let buttonInset: CGFloat = 4

    /// The tile's rectangle in panel coordinates (top-left origin).
    func tileFrame(at index: Int) -> CGRect? {
        guard index >= 0, index < count else { return nil }
        let item = itemSize
        let row = index / columns, col = index % columns
        let n = itemsInRow(row)
        let rowWidth = CGFloat(n) * item.width + CGFloat(n - 1) * Self.spacing
        let x = (panelSize.width - rowWidth) / 2 + CGFloat(col) * (item.width + Self.spacing)
        let y = Self.padding + CGFloat(row) * (item.height + Self.spacing)
        return CGRect(x: x, y: y, width: item.width, height: item.height)
    }

    /// The close / quit button's rectangle: the tile's top-right corner.
    func buttonFrame(at index: Int) -> CGRect? {
        guard let tile = tileFrame(at: index) else { return nil }
        return CGRect(x: tile.maxX - Self.buttonInset - Self.buttonSize, y: tile.minY + Self.buttonInset,
                      width: Self.buttonSize, height: Self.buttonSize)
    }

    /// The tile, or its button, under `point` (top-left origin). The button's hit
    /// area is a little larger than it looks, so it's easy to hit.
    func hit(at point: CGPoint) -> SwitcherHit? {
        guard let index = index(at: point) else { return nil }
        if let button = buttonFrame(at: index), button.insetBy(dx: -3, dy: -3).contains(point) {
            return .button(index)
        }
        return .tile(index)
    }

    /// Index of the tile under `point` (top-left origin), if any.
    func index(at point: CGPoint) -> Int? {
        let item = itemSize
        let y = point.y - Self.padding
        guard y >= 0 else { return nil }
        let row = Int(y / (item.height + Self.spacing))
        guard row < rows, y - CGFloat(row) * (item.height + Self.spacing) <= item.height else { return nil }
        let n = itemsInRow(row)
        let rowWidth = CGFloat(n) * item.width + CGFloat(n - 1) * Self.spacing
        let x = point.x - (panelSize.width - rowWidth) / 2
        guard x >= 0 else { return nil }
        let col = Int(x / (item.width + Self.spacing))
        guard col < n, x - CGFloat(col) * (item.width + Self.spacing) <= item.width else { return nil }
        return row * columns + col
    }
}
