import Testing
import Foundation
@testable import XCMCPCore

/// Tests for the artifacts a `swift-frontend` crash leaves behind: the untruncated argv, the replay
/// script, and the driver temporaries the replay needs.
struct CompilerCrashReportTests {
    /// A crash handler preamble in the shape LLVM prints it.
    private static let crashOutput = """
        Please submit a bug report and include the crash backtrace.
        Stack dump:
        0.\tProgram arguments: /usr/bin/swift-frontend -frontend -c -filelist /var/tmp/sources-1 \
        -supplementary-output-file-map /var/tmp/map-2 -module-name TobaData -O -o /tmp/out.o
        1.\tRunning pass "cgscc(devirt<4>(inline,function-attrs))" on module "TobaData"
        <unknown>:0: error: compile command failed due to signal 11 (use -v to see invocation)
        """

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("crash-\(UUID().uuidString)")
    }

    // MARK: - Argument extraction

    @Test
    func `the whole frontend argv survives the crash preamble`() {
        let argv = ErrorExtractor.extractFrontendArguments(from: Self.crashOutput)

        // The parsed summary cuts this at -plugin-path. The argv is the one untruncated copy.
        #expect(argv?.first == "/usr/bin/swift-frontend")
        #expect(argv?.contains("-supplementary-output-file-map") == true)
        #expect(argv?.last == "/tmp/out.o")
    }

    @Test
    func `output without a crash preamble yields no argv`() {
        #expect(ErrorExtractor.extractFrontendArguments(from: "Build complete!") == nil)
    }

    // MARK: - Replay script

    @Test
    func `a crash writes a runnable replay script and an argv file`() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A window of zero minutes keeps the test off whatever .ips files the machine happens to
        // hold, so the assertions cover the artifacts this code writes.
        let artifacts = CompilerCrashReport.write(
            signal: 11, from: Self.crashOutput, into: directory, reportWindowMinutes: 0,
        )

        let scriptPath = try #require(artifacts.replayScriptPath)
        let argvPath = try #require(artifacts.argvPath)

        let script = try String(contentsOfFile: scriptPath, encoding: .utf8)
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("'/usr/bin/swift-frontend'"))
        #expect(script.contains("signal 11"))

        let permissions = try FileManager.default.attributesOfItem(
            atPath: scriptPath)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o755)

        let argv = try String(contentsOfFile: argvPath, encoding: .utf8)
        #expect(argv.contains("\n-frontend\n"))
    }

    @Test
    func `output without a crash preamble writes no artifacts`() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifacts = CompilerCrashReport.write(
            signal: 11, from: "Build complete!", into: directory, reportWindowMinutes: 0,
        )

        #expect(artifacts.replayScriptPath == nil)
        #expect(artifacts.argvPath == nil)
    }

    @Test
    func `an argument containing a quote stays one argument`() {
        let quoted = CompilerCrashReport.shellQuoted("-DMESSAGE=it's fine")

        #expect(quoted == #"'-DMESSAGE=it'\''s fine'"#)
    }

    // MARK: - Driver temporaries

    @Test
    func `a deleted driver file list is reported as missing`() {
        let argv = [
            "/usr/bin/swift-frontend", "-frontend",
            "-filelist", "/var/tmp/does-not-exist-sources",
            "-module-name", "TobaData",
        ]

        // The driver deletes its file lists on exit, so a replay against the printed argv fails
        // with no explanation unless the report names them.
        #expect(
            CompilerCrashReport.missingTemporaryInputs(
                in: argv)
                == ["/var/tmp/does-not-exist-sources"],
        )
    }

    @Test
    func `a preserved driver file list is not reported as missing`() throws {
        let directory = scratchDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let filelist = directory.appendingPathComponent("sources-1")
        try "A.swift\n".write(to: filelist, atomically: true, encoding: .utf8)

        let argv = ["/usr/bin/swift-frontend", "-filelist", filelist.path]

        #expect(CompilerCrashReport.missingTemporaryInputs(in: argv).isEmpty)
    }

    @Test
    func `the report names the missing temporaries and how to keep them`() {
        let artifacts = CompilerCrashReport.Artifacts(
            directory: "/tmp/crash",
            argvPath: "/tmp/crash/frontend-argv.txt",
            replayScriptPath: "/tmp/crash/replay.sh",
            missingTemporaryInputs: ["/var/tmp/sources-1"],
            crashReportPath: nil,
            crashSummary: nil,
            writeFailure: nil,
        )

        let text = artifacts.formatted()
        #expect(text.contains("/tmp/crash/replay.sh"))
        #expect(text.contains("/var/tmp/sources-1"))
        #expect(text.contains("-save-temps"))
    }

    // MARK: - Write failures

    @Test
    func `an unwritable crash directory reports the reason`() {
        // A silent nil path would read as "the crash printed no argv", which sends the next reader
        // looking for the wrong thing.
        let artifacts = CompilerCrashReport.write(
            signal: 11,
            from: Self.crashOutput,
            into: URL(fileURLWithPath: "/dev/null/crash"),
            reportWindowMinutes: 0,
        )

        #expect(artifacts.argvPath == nil)
        #expect(artifacts.writeFailure != nil)
        #expect(artifacts.formatted().contains("failed:"))
    }

    @Test
    func `a crash with no argv reports no write failure`() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifacts = CompilerCrashReport.write(
            signal: 11, from: "Build complete!", into: directory, reportWindowMinutes: 0,
        )

        #expect(artifacts.writeFailure == nil)
    }

    @Test
    func `an argv passed in directly is not re-parsed from the output`() {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifacts = CompilerCrashReport.write(
            signal: 11,
            argv: ["/usr/bin/swift-frontend", "-frontend", "-c"],
            into: directory,
            reportWindowMinutes: 0,
        )

        #expect(artifacts.replayScriptPath != nil)
    }
}
