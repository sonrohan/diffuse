import Foundation
import XCTest

final class ProcessDeadlockTests: XCTestCase {

    /// Tests that running a process that generates output exceeding the standard 64KB pipe buffer size
    /// does not deadlock when standardOutput is drained before calling waitUntilExit().
    func testLargeProcessOutputDoesNotDeadlock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Output 100,000 lines of "hello world", which is approx 1.2MB of text (far exceeding 64KB)
        process.arguments = ["-c", "for i in {1..100000}; do echo 'hello world'; done"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Actively drain the buffer before waiting for the process to exit
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertFalse(data.isEmpty)
        let outputString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(
            outputString.components(separatedBy: .newlines).filter { !$0.isEmpty }.count, 100000)
    }

    /// Tests that when standardError is redirected to FileHandle.nullDevice,
    /// a process generating large amounts of stderr output does not deadlock.
    func testLargeProcessStderrDoesNotDeadlock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Output 50,000 lines to stderr
        process.arguments = ["-c", "for i in {1..50000}; do echo 'error line' >&2; done"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Actively drain the stdout buffer (which will be empty)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertTrue(data.isEmpty)
    }
}
