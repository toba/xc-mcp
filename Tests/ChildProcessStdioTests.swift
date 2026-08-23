import Testing
import Foundation
import TobaTesting
@testable import XCMCPCore

/// Holds the rule that no process this codebase spawns inherits the caller's standard descriptors.
///
/// `swift-test` reads the test binary's stdout pipe until every writer closes it. A child that
/// inherits file descriptor 1 and outlives the binary keeps that pipe open, and the run appears to
/// hang for the whole lifetime of the child. The same shape reaches production through any
/// long-running recording the server starts and then outlives.
@Suite(.temporaryDirectory)
struct ChildProcessStdioTests {
    /// Shell that reports whether its own stdout is the null device.
    ///
    /// `exec 3>&1` copies stdout before the redirect below rebinds it, so the comparison reads the
    /// descriptor the process was launched with. `%Hr:%Lr` prints the major and minor device
    /// numbers, which identify `/dev/null` regardless of the path used to open it.
    private static func stdoutProbe(writingTo path: String) -> [String] {
        [
            "-c",
            """
            exec 3>&1
            if [ "$(stat -f %Hr:%Lr /dev/fd/3)" = "$(stat -f %Hr:%Lr /dev/null)" ]
            then echo null > "$0"
            else echo other > "$0"
            fi
            """,
            path,
        ]
    }

    /// Reads the probe's one-word answer, or an empty string while the file is still unwritten.
    private static func verdict(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @Test
    func `A test child writes to the null device, not the test binary stdout`() async throws {
        let report = TemporaryDirectory.url.appendingPathComponent("fd1.txt").path

        let child = try TestChildProcess.launch("/bin/sh", Self.stdoutProbe(writingTo: report))
        // The redirect creates the file before the echo fills it, so presence alone is not enough.
        await expectEventually("the probe writes its report") { !Self.verdict(at: report).isEmpty }
        await child.terminateTree()

        #expect(Self.verdict(at: report) == "null")
    }

    @Test
    func `An xcrun recording never inherits the caller's descriptors`() {
        // A recording runs for minutes and no caller reads either stream, so all three descriptors
        // must be bound before launch. A nil value here means the child inherits ours.
        let process = Process.xcrun("simctl", arguments: ["io", "booted", "recordVideo", "/tmp/x"])

        #expect(process.standardInput != nil)
        #expect(process.standardOutput != nil)
        #expect(process.standardError != nil)
    }
}
