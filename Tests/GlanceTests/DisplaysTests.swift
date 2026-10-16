import XCTest
@testable import Glance

final class DisplaysTests: XCTestCase {
    // AppKit frames: a 1728×1117 primary, a 2560×1440 display to its right whose
    // bottom lines up with the primary's, and a 1920×1080 display above the primary.
    private let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let right = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
    private let above = CGRect(x: 0, y: 1117, width: 1920, height: 1080)
    private var frames: [CGRect] { [primary, right, above] }

    func testConvertsTopLeftToBottomLeft() {
        let rect = Displays.appKitRect(CGRect(x: 10, y: 20, width: 100, height: 50), primaryHeight: 1117)
        XCTAssertEqual(rect, CGRect(x: 10, y: 1047, width: 100, height: 50))
    }

    func testWindowOnPrimary() {
        XCTAssertEqual(Displays.screenIndex(for: CGRect(x: 100, y: 100, width: 800, height: 600), in: frames), 0)
    }

    func testWindowOnRightDisplay() {
        // Top-left coordinates: the right display spans y -323…1117.
        XCTAssertEqual(Displays.screenIndex(for: CGRect(x: 2000, y: -200, width: 900, height: 700), in: frames), 1)
    }

    func testWindowOnDisplayAbove() {
        // Negative y in CGWindowList coordinates is above the primary display.
        XCTAssertEqual(Displays.screenIndex(for: CGRect(x: 200, y: -900, width: 800, height: 600), in: frames), 2)
    }

    func testStraddlingWindowGoesToLargerOverlap() {
        // 200 pt on the primary, 600 pt on the right display.
        XCTAssertEqual(Displays.screenIndex(for: CGRect(x: 1528, y: 100, width: 800, height: 600), in: frames), 1)
    }

    func testOffscreenWindowHasNoDisplay() {
        XCTAssertNil(Displays.screenIndex(for: CGRect(x: -5000, y: 100, width: 300, height: 300), in: frames))
        XCTAssertNil(Displays.screenIndex(for: CGRect(x: 0, y: 0, width: 300, height: 300), in: []))
    }
}
