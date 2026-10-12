import XCTest
@testable import Glance

@MainActor
final class WindowMRUTests: XCTestCase {
    private func window(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, title: "\(id)", appName: "App", bounds: .zero, icon: nil)
    }

    func testRecentWindowOnAnotherSpaceComesSecond() {
        // You were watching a full-screen video (99), then switched to desktop window 1.
        let mru = WindowMRU()
        mru.touch(99)
        let order = mru.order(current: [window(1), window(2)], others: [window(99)])
        XCTAssertEqual(order.map(\.id), [1, 99, 2])
    }

    func testUnseenOtherSpaceWindowsGoLast() {
        let mru = WindowMRU()
        let order = mru.order(current: [window(1), window(2)], others: [window(7), window(8)])
        XCTAssertEqual(order.map(\.id), [1, 2, 7, 8])
    }

    func testCurrentSpaceZOrderWinsOverStaleStamps() {
        // Stamps say 2 is newer, but on screen 1 is in front of 2 and 3.
        let mru = WindowMRU()
        mru.touch(3)
        mru.touch(2)
        let order = mru.order(current: [window(1), window(3), window(2)], others: [])
        XCTAssertEqual(order.map(\.id), [1, 3, 2])
    }

    func testFromFullScreenVideoPreviousDesktopWindowIsSecond() {
        // On the video's Space: only the video is current; desktop windows are elsewhere.
        let mru = WindowMRU()
        mru.touch(2)
        mru.touch(1) // last desktop window used before going full screen
        let order = mru.order(current: [window(99)], others: [window(2), window(1), window(5)])
        XCTAssertEqual(order.map(\.id), [99, 1, 2, 5])
    }
}
