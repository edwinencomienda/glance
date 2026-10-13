import XCTest
@testable import Glance

final class WindowListTests: XCTestCase {
    private let browser = CGRect(x: 0, y: 33, width: 1512, height: 897)

    func testAddressBarSuggestionsArePopup() {
        // Edge's suggestion list, measured from the real window list.
        let suggestions = CGRect(x: 64, y: 73, width: 1091, height: 319)
        XCTAssertTrue(WindowList.isPopup(suggestions, over: [browser]))
    }

    func testPopupHangingPastWindowEdgeIsPopup() {
        let dropdown = CGRect(x: 1300, y: 800, width: 400, height: 300)
        XCTAssertTrue(WindowList.isPopup(dropdown, over: [browser]))
    }

    func testSeparateUntitledWindowIsKept() {
        let elsewhere = CGRect(x: 1600, y: 100, width: 600, height: 400)
        XCTAssertFalse(WindowList.isPopup(elsewhere, over: [browser]))
    }

    func testUntitledWindowLargerThanTitledOneIsKept() {
        let palette = CGRect(x: 100, y: 100, width: 300, height: 300)
        XCTAssertFalse(WindowList.isPopup(browser, over: [palette]))
    }

    func testUntitledOnlyWindowIsKept() {
        XCTAssertFalse(WindowList.isPopup(browser, over: []))
    }

    func testShortTitledWindowIsKept() {
        // Finder's "Emptying the Trash…" progress window.
        XCTAssertTrue(WindowList.isSwitchableSize(CGSize(width: 404, height: 88), titled: true))
    }

    func testShortUntitledWindowIsDropped() {
        XCTAssertFalse(WindowList.isSwitchableSize(CGSize(width: 1920, height: 30), titled: false))
        XCTAssertFalse(WindowList.isSwitchableSize(CGSize(width: 404, height: 88), titled: false))
    }

    func testTinyTitledWindowIsDropped() {
        XCTAssertFalse(WindowList.isSwitchableSize(CGSize(width: 300, height: 30), titled: true))
    }
}
