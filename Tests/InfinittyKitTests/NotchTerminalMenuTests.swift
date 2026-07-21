import AppKit
import XCTest

@testable import InfinittyKit

final class NotchTerminalMenuTests: XCTestCase {
    func testCompactMenuSitsLeftOfBuiltinNotch() {
        let screen = NSRect(x: 0, y: 0, width: 1_512, height: 982)
        let frame = NotchTerminalMenuLayout.frame(in: screen, safeAreaTop: 32)

        XCTAssertEqual(frame.width, 34)
        XCTAssertEqual(frame.height, 32)
        XCTAssertEqual(frame.maxX, screen.midX - 110)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }

    func testCompactMenuCentersOnDisplayWithoutNotch() {
        let screen = NSRect(x: 100, y: 50, width: 1_920, height: 1_080)
        let frame = NotchTerminalMenuLayout.frame(in: screen, safeAreaTop: 0)

        XCTAssertEqual(frame.width, 34)
        XCTAssertEqual(frame.height, 26)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }

    func testCompactMenuAvoidsActivityOnDisplayWithoutNotch() {
        let screen = NSRect(x: 100, y: 50, width: 1_920, height: 1_080)
        let frame = NotchTerminalMenuLayout.frame(
            in: screen,
            safeAreaTop: 0,
            avoidingActivity: true)

        XCTAssertEqual(
            frame.maxX,
            screen.midX
                - NotchTerminalMenuLayout.activityWidth / 2
                - NotchTerminalMenuLayout.activityGap)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }
}
