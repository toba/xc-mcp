import Testing
import Foundation
@testable import XCMCPCore

struct RawBuildLogTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("xc-mcp-rawlog-test-\(UUID().uuidString).log")
    }

    @Test
    func `Stores and loads raw output with metadata`() throws {
        let url = tempURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("json"))
        }

        let raw = "duplicate symbol '_x' in:\n    a.o\n    b.o\nld: 1 duplicate symbol\n"
        RawBuildLog.store(
            rawOutput: raw, action: "build", destination: "platform=macOS", succeeded: false,
            to: url,
        )

        let capture = try #require(RawBuildLog.load(from: url))
        #expect(capture.rawOutput == raw)
        #expect(capture.path == url.path)
        let meta = try #require(capture.metadata)
        #expect(meta.action == "build")
        #expect(meta.destination == "platform=macOS")
        #expect(meta.succeeded == false)
        #expect(meta.byteCount == raw.utf8.count)
    }

    @Test
    func `Load returns nil when nothing captured`() {
        #expect(RawBuildLog.load(from: tempURL()) == nil)
    }

    @Test
    func `Empty output does not clobber an existing capture`() throws {
        let url = tempURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("json"))
        }

        RawBuildLog.store(
            rawOutput: "real diagnostics", action: "build", destination: "platform=macOS",
            succeeded: false, to: url,
        )
        // A subsequent no-op capture must not overwrite the real one.
        RawBuildLog.store(
            rawOutput: "", action: "build", destination: "platform=macOS", succeeded: true,
            to: url,
        )

        let capture = try #require(RawBuildLog.load(from: url))
        #expect(capture.rawOutput == "real diagnostics")
    }
}
