import AppKit
import XCTest

@testable import InfinittyKit

final class DetachedTerminalTests: XCTestCase {
    func testDisplayTitlePreservesCustomNameAndPaneCount() {
        let first = TerminalSession(config: AppConfig(), scale: 2)
        let second = TerminalSession(config: AppConfig(), scale: 2)
        defer {
            first.shutdown()
            second.shutdown()
        }
        let root = NSSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        root.addArrangedSubview(first.view)
        root.addArrangedSubview(second.view)
        let detached = DetachedTerminal(
            rootView: root,
            customTitle: "Build Logs",
            preferredFocus: second.view)

        XCTAssertEqual(
            detached.displayTitle(sessions: [first, second]),
            "Build Logs (2)")
    }

    func testExitedPaneCollapsesRetainedRootSplit() {
        let first = TerminalSession(config: AppConfig(), scale: 2)
        let second = TerminalSession(config: AppConfig(), scale: 2)
        defer {
            first.shutdown()
            second.shutdown()
        }
        let frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        let root = NSSplitView(frame: frame)
        root.addArrangedSubview(first.view)
        root.addArrangedSubview(second.view)
        let detached = DetachedTerminal(
            rootView: root,
            customTitle: nil,
            preferredFocus: second.view)

        detached.removePane(first.view)

        XCTAssertTrue(detached.rootView === second.view)
        XCTAssertEqual(second.view.frame, frame)
        XCTAssertFalse(detached.contains(first.view))
        XCTAssertTrue(detached.contains(second.view))
    }
}
