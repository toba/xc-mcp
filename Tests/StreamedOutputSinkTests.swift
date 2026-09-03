import MCP
import Testing
import Foundation
@testable import XCMCPCore

/// Tests for the sink that keeps a gigabyte-scale compiler probe out of an MCP response.
struct StreamedOutputSinkTests {
    /// A unique scratch path that the caller removes.
    private func scratchPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sink-\(UUID().uuidString).log").path
    }

    @Test
    func `every line reaches the file when no filter is set`() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let sink = try StreamedOutputSink(path: path, filter: nil)
        sink.receive("first\nsecond\n")
        sink.receive("third\n")
        let summary = sink.finish()

        #expect(summary.linesSeen == 3)
        #expect(summary.linesWritten == 3)
        #expect(summary.lastLine == "third")
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "first\nsecond\nthird\n")
    }

    @Test
    func `a filter keeps only the matching lines`() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let sink = try StreamedOutputSink(path: path, filter: "^BISECT")
        sink.receive("Running pass one\nBISECT: running pass (17)\nRunning pass two\n")
        sink.receive("BISECT: running pass (18)\n")
        let summary = sink.finish()

        #expect(summary.linesSeen == 4)
        #expect(summary.linesWritten == 2)
        #expect(summary.lastLine == "BISECT: running pass (18)")

        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!written.contains("Running pass"))
    }

    @Test
    func `a line split across two chunks is matched whole`() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // The subprocess reader splits at arbitrary byte boundaries, so a filter that ran per chunk
        // would test "BIS" against the pattern and drop the line.
        let sink = try StreamedOutputSink(path: path, filter: "^BISECT")
        sink.receive("BIS")
        sink.receive("ECT: running pass (17)\n")
        let summary = sink.finish()

        #expect(summary.linesWritten == 1)
        #expect(summary.lastLine == "BISECT: running pass (17)")
    }

    @Test
    func `a trailing line with no newline is flushed on finish`() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // The answer to an -opt-bisect-limit probe is the last line, and a crashed compiler often
        // leaves it without a terminating newline.
        let sink = try StreamedOutputSink(path: path, filter: nil)
        sink.receive("complete\nincomplete")
        let summary = sink.finish()

        #expect(summary.linesSeen == 2)
        #expect(summary.lastLine == "incomplete")
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "complete\nincomplete\n")
    }

    @Test
    func `a colored line reaches the file as plain text`() throws {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // The filter pattern is written against the message, so a line that kept its color codes
        // would never match it.
        let sink = try StreamedOutputSink(path: path, filter: "error:")
        sink.receive("\u{1B}[0;1mFoo.swift:1:1: \u{1B}[0;1;31merror: \u{1B}[0mno such module\n")
        let summary = sink.finish()

        let written = try String(contentsOfFile: path, encoding: .utf8)

        #expect(summary.linesWritten == 1)
        #expect(summary.lastLine == "Foo.swift:1:1: error: no such module")
        #expect(!written.contains("\u{1B}"))
    }

    @Test
    func `an invalid filter is rejected before the build starts`() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(throws: StreamedOutputSink.SinkError.self) {
            _ = try StreamedOutputSink(path: path, filter: "[unterminated")
        }
    }

    @Test
    func `an unwritable path is rejected before the build starts`() {
        #expect(throws: StreamedOutputSink.SinkError.self) {
            _ = try StreamedOutputSink(path: "/dev/null/nested/probe.log", filter: nil)
        }
    }
}
