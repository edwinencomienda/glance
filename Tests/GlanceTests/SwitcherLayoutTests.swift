import XCTest
@testable import Glance

final class SwitcherLayoutTests: XCTestCase {
    private let screen = CGSize(width: 1728, height: 1080)

    func testSingleWindowIsOneTile() {
        let layout = SwitcherLayout.make(count: 1, in: screen)
        XCTAssertEqual(layout.columns, 1)
        XCTAssertEqual(layout.rows, 1)
    }

    func testFewWindowsFitOnOneRow() {
        let layout = SwitcherLayout.make(count: 4, in: screen)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.columns, 4)
    }

    func testPanelAlwaysFitsScreen() {
        for count in 1...60 {
            let layout = SwitcherLayout.make(count: count, in: screen)
            XCTAssertGreaterThanOrEqual(layout.columns * layout.rows, count, "count \(count)")
            XCTAssertLessThanOrEqual(layout.panelSize.width, screen.width * 0.9, "count \(count)")
        }
    }

    func testRowsAreBalanced() {
        // 7 windows that wrap should not leave a single orphan on the last row.
        let layout = SwitcherLayout.make(count: 7, in: CGSize(width: 1280, height: 800))
        XCTAssertGreaterThan(layout.itemsInRow(layout.rows - 1), 1)
    }

    func testSettingsAffectTileSize() {
        let withTitles = SwitcherLayout.make(count: 3, in: screen, thumbWidth: 176, showTitles: true)
        let noTitles = SwitcherLayout.make(count: 3, in: screen, thumbWidth: 176, showTitles: false)
        XCTAssertEqual(withTitles.thumbSize.width, 176)
        XCTAssertEqual(noTitles.titleHeight, 0)
        XCTAssertEqual(withTitles.itemSize.height - noTitles.itemSize.height, SwitcherLayout.defaultTitleHeight)
    }

    func testIconModeUsesCompactTiles() {
        let icons = SwitcherLayout.make(count: 6, in: screen, thumbWidth: 104, iconsOnly: true)
        let thumbs = SwitcherLayout.make(count: 6, in: screen)
        XCTAssertTrue(icons.iconsOnly)
        XCTAssertEqual(icons.thumbSize.height, 62, "icon is 60% of the tile width")
        XCTAssertLessThan(icons.itemSize.width, thumbs.itemSize.width)
        XCTAssertGreaterThanOrEqual(icons.columns, thumbs.columns, "more icons fit per row")
    }

    func testHitTestingMatchesTiles() {
        let layout = SwitcherLayout.make(count: 5, in: screen)
        let item = layout.itemSize
        let p = SwitcherLayout.padding, s = SwitcherLayout.spacing
        let rowWidth = CGFloat(layout.itemsInRow(0)) * item.width + CGFloat(layout.itemsInRow(0) - 1) * s
        let startX = (layout.panelSize.width - rowWidth) / 2

        XCTAssertEqual(layout.index(at: CGPoint(x: startX + item.width / 2, y: p + item.height / 2)), 0)
        XCTAssertEqual(layout.index(at: CGPoint(x: startX + item.width * 1.5 + s, y: p + 10)), 1)
        XCTAssertNil(layout.index(at: CGPoint(x: 2, y: 2)), "padding is not a tile")
        XCTAssertNil(layout.index(at: CGPoint(x: startX + item.width + s / 2, y: p + 10)), "gap is not a tile")
    }

    func testTileFramesMatchHitTesting() {
        let layout = SwitcherLayout.make(count: 7, in: CGSize(width: 1280, height: 800))
        for i in 0..<layout.count {
            let frame = try! XCTUnwrap(layout.tileFrame(at: i))
            XCTAssertEqual(layout.index(at: CGPoint(x: frame.midX, y: frame.midY)), i, "tile \(i)")
        }
        XCTAssertNil(layout.tileFrame(at: layout.count))
    }

    func testButtonSitsInTileTopRightCorner() {
        let layout = SwitcherLayout.make(count: 3, in: screen)
        let tile = try! XCTUnwrap(layout.tileFrame(at: 1))
        let button = try! XCTUnwrap(layout.buttonFrame(at: 1))
        XCTAssertTrue(tile.contains(button))
        XCTAssertEqual(tile.maxX - button.maxX, SwitcherLayout.buttonInset)
        XCTAssertEqual(button.minY - tile.minY, SwitcherLayout.buttonInset)
    }

    func testHitDistinguishesButtonFromTile() {
        let layout = SwitcherLayout.make(count: 3, in: screen)
        let tile = try! XCTUnwrap(layout.tileFrame(at: 2))
        let button = try! XCTUnwrap(layout.buttonFrame(at: 2))
        XCTAssertEqual(layout.hit(at: CGPoint(x: button.midX, y: button.midY)), .button(2))
        XCTAssertEqual(layout.hit(at: CGPoint(x: button.minX - 2, y: button.midY)), .button(2), "slightly forgiving")
        XCTAssertEqual(layout.hit(at: CGPoint(x: tile.midX, y: tile.midY)), .tile(2))
        XCTAssertEqual(layout.hit(at: CGPoint(x: tile.minX + 5, y: tile.minY + 5)), .tile(2), "top-left is the tile")
        XCTAssertNil(layout.hit(at: CGPoint(x: 1, y: 1)))
    }
}
