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

    func testPreviewTemporarilyHostsAndReleasesDetachedTree() {
        _ = NSApplication.shared
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let detached = DetachedTerminal(
            rootView: root,
            customTitle: "Preview",
            preferredFocus: nil)
        let preview = DetachedTerminalPreviewController()

        let window = preview.present(detached, title: "Preview", activate: false)
        XCTAssertTrue(preview.detached === detached)
        XCTAssertTrue(window.contentView === root)
        XCTAssertTrue(root.window === window)

        XCTAssertTrue(preview.dismiss(ifPresenting: detached))
        XCTAssertNil(preview.detached)
        XCTAssertNil(preview.window)
        XCTAssertNil(root.window)
        XCTAssertFalse(preview.dismiss(ifPresenting: detached))
    }

    func testPreviewRefreshesWhenDetachedRootSplitCollapses() {
        _ = NSApplication.shared
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
            customTitle: nil,
            preferredFocus: second.view)
        let preview = DetachedTerminalPreviewController()
        let window = preview.present(detached, title: "Preview", activate: false)

        detached.removePane(first.view)
        preview.refreshRoot()

        XCTAssertTrue(detached.rootView === second.view)
        XCTAssertTrue(window.contentView === second.view)
        preview.dismiss()
    }

    func testPreviewReturnsToDetachedAfterFocusLoss() {
        _ = NSApplication.shared
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let detached = DetachedTerminal(
            rootView: root,
            customTitle: nil,
            preferredFocus: nil)
        let preview = DetachedTerminalPreviewController()
        let window = preview.present(detached, title: "Preview", activate: false)

        preview.windowDidResignKey(Notification(
            name: NSWindow.didResignKeyNotification,
            object: window))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))

        XCTAssertNil(preview.window)
        XCTAssertNil(root.window)
        XCTAssertTrue(detached.rootView === root)
    }
}
