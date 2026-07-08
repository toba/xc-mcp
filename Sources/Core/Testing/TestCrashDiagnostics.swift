import Foundation

/// Surfaces the *cause* of a test-process crash that xcodebuild reports only as a bare "Test
/// crashed with signal trap."
///
/// When a Swift trap (`fatalError`, `precondition`, `assert`) or an Objective-C exception kills the
/// test host, the diagnostic text is written to the test host's stderr and to the unified log —
/// never to the xcresult bundle, and never to a fresh `.ips` once the OS has deduped the signature.
/// This helper recovers those two channels:
///
/// 1. Swift trap / ObjC exception lines scraped from the captured test-host stderr.
/// 2. Fatal/exception lines pulled from the unified log (`log show`) scoped to the test run's
///    wall-clock window.
public enum TestCrashDiagnostics {
    /// Substrings in xcodebuild/xcresult output that indicate the test *process* died abnormally
    /// (as opposed to an ordinary `XCTAssert` failure).
    static let crashSignatures = [
        "crashed with signal",
        "Test crashed",
        "did crash",
        "signal trap",
        "Restarting after unexpected exit",
        "encountered an error (Crash:",
    ]

    /// Substrings that mark a line as a Swift trap or an Objective-C exception.
    static let trapSignatures = [
        "Fatal error:",
        "Precondition failed:",
        "Assertion failed:",
        "Thread 0: Fatal error",
        "Terminating app due to uncaught exception",
        "*** Terminating app",
        "libc++abi:",
        "*** First throw call stack",
        "uncaught exception",
        "NSException",
        "EXC_BAD_ACCESS",
        "EXC_BAD_INSTRUCTION",
        "EXC_CRASH",
        "BUG IN CLIENT OF",
        "_dispatch_assert_queue_fail",
        "dispatch_assert_queue",
        "Abort trap: 6",
        "SIGABRT",
        "Swift runtime failure:",
        "ERROR: AddressSanitizer",
        "ERROR: ThreadSanitizer",
        "ERROR: UndefinedBehaviorSanitizer",
    ]

    /// Returns `true` when the combined test output looks like a process crash rather than a plain
    /// assertion failure.
    public static func detectCrash(in output: String) -> Bool {
        crashSignatures.contains { output.contains($0) }
    }

    /// Scrapes Swift trap and Objective-C exception lines out of a captured stream (the test host's
    /// stderr or stdout).
    ///
    /// Trap lines are noisy in context, so this keeps only lines that carry a known signature,
    /// de-duplicates them, and preserves order.
    public static func extractTrapLines(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard trapSignatures.contains(where: { line.contains($0) }) else { continue }
            if seen.insert(line).inserted { result.append(line) }
        }
        return result
    }

    /// `log show` accepts wall-clock timestamps in `YYYY-MM-DD HH:MM:SS` form.
    static func logTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Predicate that matches Swift traps and Objective-C exceptions in the unified log, optionally
    /// narrowed to a single process.
    static func fatalLogPredicate(processName: String?) -> String {
        let content = [
            "composedMessage CONTAINS \"Fatal error\"",
            "composedMessage CONTAINS \"Precondition failed\"",
            "composedMessage CONTAINS \"Assertion failed\"",
            "composedMessage CONTAINS \"Terminating app due to uncaught exception\"",
            "composedMessage CONTAINS \"NSException\"",
            "composedMessage CONTAINS \"BUG IN CLIENT\"",
            "composedMessage CONTAINS \"Abort trap\"",
            "composedMessage CONTAINS \"EXC_CRASH\"",
            "composedMessage CONTAINS \"Swift runtime failure\"",
            "composedMessage CONTAINS \"ERROR: AddressSanitizer\"",
            "composedMessage CONTAINS \"ERROR: ThreadSanitizer\"",
        ].joined(separator: " OR ")
        let contentClause = "(\(content))"
        guard let processName, !processName.isEmpty else { return contentClause }
        let escaped = processName.replacingOccurrences(of: "\"", with: "\\\"")
        return "process == \"\(escaped)\" AND \(contentClause)"
    }

    /// Queries the unified log for fatal/exception lines emitted during the test run window. The
    /// window is padded by two seconds on each side to absorb clock skew between the harness and
    /// the log database.
    ///
    /// - Returns: Matching log lines (compact style), or an empty array if the query found nothing
    ///   or failed.
    public static func queryFatalLog(
        start: Date,
        end: Date,
        processName: String? = nil,
        simulatorUDID: String? = nil,
    ) async -> [String] {
        let predicate = fatalLogPredicate(processName: processName)
        let logArgs = [
            "show",
            "--style", "compact",
            "--start", logTimestamp(start.addingTimeInterval(-2)),
            "--end", logTimestamp(end.addingTimeInterval(2)),
            "--predicate", predicate,
        ]
        let executable: String
        let arguments: [String]

        if let simulatorUDID, !simulatorUDID.isEmpty {
            // Simulator processes log to the sim's own logd, not the host's unified log.
            executable = "/usr/bin/xcrun"
            arguments = ["simctl", "spawn", simulatorUDID, "log"] + logArgs
        } else {
            executable = "/usr/bin/log"
            arguments = logArgs
        }
        guard let result = try? await ProcessResult.run(
            executable, arguments: arguments, timeout: .seconds(30),
        ) else { return [] }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Filtering the log data") }
    }

    /// Builds a human-readable "Crash diagnosis" section, or `nil` when no crash-cause evidence
    /// could be recovered.
    ///
    /// - Parameters:
    ///   - stderr: The captured test-host stderr (and/or stdout) to scrape.
    ///   - logWindow: Optional `(start, end)` wall-clock window. When supplied, the unified log is
    ///     queried for fatal/exception lines in that window.
    ///   - processName: Optional test-host process name to narrow the log query.
    public static func diagnose(
        stderr: String?,
        logWindow: (start: Date, end: Date)? = nil,
        processName: String? = nil,
        simulatorUDID: String? = nil,
    ) async -> String? {
        var sections: [String] = []

        let trapLines = stderr.map(extractTrapLines) ?? []

        if !trapLines.isEmpty {
            sections.append(
                "Test-host stderr:\n" + trapLines.map { "  \($0)" }.joined(separator: "\n"),
            )
        }

        if let logWindow {
            let logLines = await queryFatalLog(
                start: logWindow.start, end: logWindow.end,
                processName: processName, simulatorUDID: simulatorUDID,
            )

            if !logLines.isEmpty {
                // The compact log lines can be long; keep the most recent 40.
                let trimmed = logLines.suffix(40)
                sections.append(
                    "Unified log (fatal/exception):\n"
                        + trimmed.map { "  \($0)" }.joined(separator: "\n"),
                )
            }
        }

        guard !sections.isEmpty else { return nil }

        var message = "Crash diagnosis (recovered cause of the test-process crash):\n\n"
        message += sections.joined(separator: "\n\n")
        return message
    }
}
