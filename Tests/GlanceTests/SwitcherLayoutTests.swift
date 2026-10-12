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
}
