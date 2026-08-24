import Foundation

/// Turns a `swift-frontend` crash into artifacts an agent can act on.
///
/// A crash summary in an MCP response is not enough to diagnose one. The invocation is truncated,
/// so the failing job cannot be replayed, and the only way to retry is a full package build. The OS
/// meanwhile writes a fully symbolicated backtrace to `~/Library/Logs/DiagnosticReports`, which
/// names the failing LLVM pass and the fault address, and nothing reads it.
///
/// This type writes three things into one directory and reports their paths:
///
/// 1. `frontend-argv.txt` — the whole argv, one argument per line
/// 2. `replay.sh` — an executable script that reruns that single frontend job
/// 3. the newest matching `.ips` summary, parsed into the response
public enum CompilerCrashReport {
    /// The flags whose value is a driver temporary file the replay needs.
    ///
    /// The driver deletes these when it exits, so a replay resolves them only when the build ran
    /// with `-save-temps` and a `TMPDIR` under the crash directory.
    private static let temporaryInputFlags: Set<String> = [
        "-filelist", "-output-filelist", "-supplementary-output-file-map",
    ]

    /// The directory a crash writes into, scoped by parent process so sibling focused servers under
    /// one client share it. `XC_MCP_CRASH_DIR` overrides it.
    public static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["XC_MCP_CRASH_DIR"] {
            return URL(fileURLWithPath: override)
        }
        return .init(fileURLWithPath: "/tmp/xc-mcp-compiler-crash-\(getppid())")
    }

    /// The paths and findings a crash produced.
    public struct Artifacts: Sendable {
        /// The directory holding every artifact.
        public let directory: String
        /// The file listing the frontend argv, or `nil` when the crash printed no argv.
        public let argvPath: String?
        /// The executable replay script, or `nil` when the crash printed no argv.
        public let replayScriptPath: String?
        /// Temporary inputs the replay needs that no longer exist on disk.
        public let missingTemporaryInputs: [String]
        /// The `.ips` file the OS wrote for this crash, if one was found.
        public let crashReportPath: String?
        /// The parsed crashing thread and exception from that `.ips`.
        public let crashSummary: CrashReportParser.CrashSummary?
        /// Why an artifact could not be written, when the crash did carry an argv.
        ///
        /// Without this a caller cannot tell an unwritable directory from a crash that printed no
        /// argv, because both leave ``argvPath`` and ``replayScriptPath`` nil.
        public let writeFailure: String?

        /// A report for an MCP response, empty when nothing was recovered.
        public func formatted() -> String {
            var sections: [String] = []

            if let replayScriptPath {
                var replay = "Replay the single failing frontend job:\n  sh \(replayScriptPath)"
                if let argvPath { replay += "\nFull argv, one argument per line: \(argvPath)" }
                sections.append(replay)
            }

            if let writeFailure {
                sections.append(
                    "The crash carried a replayable invocation, and writing it to \(directory) "
                        + "failed: \(writeFailure)",
                )
            }

            if !missingTemporaryInputs.isEmpty {
                var missing = "The replay is missing \(missingTemporaryInputs.count) driver "
                missing += "temporary file(s) the driver deleted on exit:\n"
                missing += missingTemporaryInputs.map { "  \($0)" }.joined(separator: "\n")
                missing += "\nRerun the build with `swiftc_flags: [\"-save-temps\"]` to keep them."
                sections.append(missing)
            }

            if let crashSummary {
                var report = "OS crash report"
                if let crashReportPath { report += " (\(crashReportPath))" }
                sections.append("\(report):\n\(crashSummary.formatted())")
            }

            return sections.joined(separator: "\n\n")
        }
    }

    /// Writes the crash artifacts and reads the matching OS crash report.
    ///
    /// - Parameters:
    ///   - signal: The signal the compiler died on.
    ///   - output: Build output that carries the crash handler preamble.
    ///   - directory: Where to write the argv file and the replay script.
    ///   - reportWindowMinutes: How far back to look for a matching `.ips`.
    /// - Returns: The artifacts, with `nil` paths when the output held no argv.
    public static func write(
        signal: Int,
        from output: String,
        into directory: URL,
        reportWindowMinutes: Int = 10,
    ) -> Artifacts {
        write(
            signal: signal,
            argv: ErrorExtractor.extractFrontendArguments(from: output),
            into: directory,
            reportWindowMinutes: reportWindowMinutes,
        )
    }

    /// Writes the crash artifacts for an argv the caller already extracted.
    ///
    /// Parsing the argv out of a verbose release build log means splitting tens of megabytes, so a
    /// caller that has already done it passes the result here rather than paying for it twice.
    ///
    /// - Parameters:
    ///   - signal: The signal the compiler died on.
    ///   - argv: The frontend argv, or `nil` when the output held no crash preamble.
    ///   - directory: Where to write the argv file and the replay script.
    ///   - reportWindowMinutes: How far back to look for a matching `.ips`.
    /// - Returns: The artifacts, with `nil` paths when `argv` is absent or the write failed.
    public static func write(
        signal: Int,
        argv: [String]?,
        into directory: URL,
        reportWindowMinutes: Int = 10,
    ) -> Artifacts {
        var argvPath: String?
        var replayScriptPath: String?
        var missing: [String] = []
        var writeFailure: String?

        if let argv, argv.count > 1 {
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true,
                )
                missing = missingTemporaryInputs(in: argv)

                let argvFile = directory.appendingPathComponent("frontend-argv.txt")
                try argv.joined(separator: "\n").write(
                    to: argvFile, atomically: true, encoding: .utf8,
                )
                argvPath = argvFile.path

                let scriptFile = directory.appendingPathComponent("replay.sh")
                try replayScript(argv: argv, signal: signal).write(
                    to: scriptFile, atomically: true, encoding: .utf8,
                )
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: scriptFile.path,
                )
                replayScriptPath = scriptFile.path
            } catch {
                writeFailure = "\(error)"
            }
        }

        let crash = CrashReportParser
            .search(processName: "swift-frontend", minutes: reportWindowMinutes).first

        return .init(
            directory: directory.path,
            argvPath: argvPath,
            replayScriptPath: replayScriptPath,
            missingTemporaryInputs: missing,
            crashReportPath: crash?.path,
            crashSummary: crash?.summary,
            writeFailure: writeFailure,
        )
    }

    /// Returns the driver temporary files the argv names that are gone from disk.
    static func missingTemporaryInputs(in argv: [String]) -> [String] {
        var missing: [String] = []

        for (
            index, token
        ) in argv.enumerated()
            where temporaryInputFlags.contains(token) && index + 1 < argv.count
        {
            let path = argv[index + 1]
            if !FileManager.default.fileExists(atPath: path) { missing.append(path) }
        }
        return missing
    }

    /// Renders a shell script that reruns one frontend invocation.
    static func replayScript(argv: [String], signal: Int) -> String {
        var lines = [
            "#!/bin/sh",
            "# Replays the single swift-frontend job that died on signal \(signal).",
            "# Rerunning this costs one compilation instead of a whole package build.",
            "# Add a probe flag by editing the argument list below.",
            "exec \\",
        ]

        for (index, argument) in argv.enumerated() {
            let continuation = index == argv.count - 1 ? "" : " \\"
            lines.append("  \(shellQuoted(argument))\(continuation)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Wraps an argument in single quotes so the shell passes it through unchanged.
    static func shellQuoted(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
