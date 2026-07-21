import Darwin
import Foundation
import XCTest

@testable import InfinittyKit

final class ControlSocketTests: XCTestCase {
    func testControlSocketsDefaultOnAndFalseRoundTripsThroughConfig() throws {
        XCTAssertTrue(AppConfig().controlSockets)

        let path = NSTemporaryDirectory()
            + "infinitty-control-sockets-\(UUID().uuidString).conf"
        try "control-sockets = false\n".write(
            toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let key = "INFINITTY_CONFIG"
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        let config = AppConfig.load()
        XCTAssertFalse(config.controlSockets)
        XCTAssertTrue(config.serialize().contains("control-sockets = false"))
    }

    func testPaneControlSocketCanStopAndRestart() {
        let server = ControlServer(
            terminal: Terminal(cols: 80, rows: 24),
            pty: PTY())
        defer { server.stop() }

        XCTAssertFalse(server.isRunning)
        server.start()
        XCTAssertTrue(server.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: server.path))

        server.stop()
        XCTAssertFalse(server.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: server.path))

        server.start()
        XCTAssertTrue(server.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: server.path))
    }

    func testAppControlSocketCanStopAndRestartWithDiscoveryLink() throws {
        let link = NSTemporaryDirectory()
            + "infinitty-current-\(UUID().uuidString).sock"
        let server = AppControlServer(discoveryLink: link)
        defer {
            server.stop()
            try? FileManager.default.removeItem(atPath: link)
        }

        server.start()
        XCTAssertTrue(server.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: server.path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: link),
            server.path)

        server.stop()
        XCTAssertFalse(server.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: server.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: link))

        server.start()
        XCTAssertTrue(server.isRunning)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: link),
            server.path)
    }

    func testDisabledSessionDoesNotExposePaneSocketPath() {
        var config = AppConfig()
        config.controlSockets = false
        let session = TerminalSession(config: config, scale: 2)
        defer { session.shutdown() }

        XCTAssertFalse(session.control.isRunning)
        XCTAssertNil(session.controlSocketPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.control.path))

        session.setControlSocketsEnabled(true)
        XCTAssertTrue(session.control.isRunning)
        XCTAssertEqual(session.controlSocketPath, session.control.path)

        session.setControlSocketsEnabled(false)
        XCTAssertFalse(session.control.isRunning)
        XCTAssertNil(session.controlSocketPath)
    }
}
