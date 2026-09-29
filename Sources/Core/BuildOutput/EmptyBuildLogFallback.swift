import Foundation

/// Reports what a build said when its `.xcactivitylog` is empty.
///
/// Xcode writes the activity log when a build ends. A build that dies first, which is what a
/// `swift-frontend` crash does, leaves a zero-byte log. The `.dia` files the compiler jobs wrote
/// still hold every diagnostic, and macOS still wrote a crash report, so this reads those.
public enum EmptyBuildLogFallback {
    /// The most `.dia` files one report decodes, newest first.
    public static let maxDiagnosticFiles = 500

    /// Builds the report for a DerivedData root whose newest build log is empty or missing.
    ///
    /// - Parameters:
    ///   - derivedDataPath: The DerivedData root of the project.
    ///   - emptyLog: The zero-byte log, when one exists. Its date marks the start of the build.
    ///   - staleLog: An older non-empty log, when one exists. It belongs to an earlier build.
    ///   - errorsOnly: Leave warnings out.
    ///   - now: The current time, for tests.
    /// - Returns: The report text.
    public static func report(
        derivedDataPath: String,
        emptyLog: BuildLogEntry?,
        staleLog: BuildLogEntry?,
        errorsOnly: Bool,
        now: Date = Date(),
    ) -> String {
        // Without an empty log to date the build, the last half hour stands in for it.
        let cutoff = emptyLog?.date.addingTimeInterval(-60) ?? now.addingTimeInterval(-30 * 60)
        let windowMinutes = max(1, Int((now.timeIntervalSince(cutoff) / 60).rounded(.up)))

        var sections: [String] = []

        if let emptyLog {
            sections.append(
                "## Build Log (\(emptyLog.formattedDate)) is empty\n\n"
                    + "Xcode writes the log when a build ends, so an empty log means the build "
                    + "died before it finished. A compiler crash does this. The diagnostics "
                    + "below come from the .dia files the compiler jobs wrote since then.",
            )
        } else {
            sections.append(
                "## No build log\n\n"
                    + "DerivedData holds no non-empty build log. The diagnostics below come "
                    + "from the .dia files written in the last \(windowMinutes) minutes.",
            )
        }

        if let staleLog, let emptyLog, staleLog.date < emptyLog.date {
            sections.append(
                "The newest non-empty log (\(staleLog.formattedDate)) is from an earlier "
                    + "build, so this report does not read it.",
            )
        }

        let intermediates = DerivedDataLocator.intermediatesPath(projectRoot: derivedDataPath)
        let diagnostics = decodeRecentDiagnostics(in: intermediates, since: cutoff)
        sections.append(format(diagnostics, errorsOnly: errorsOnly))

        if let crash = FrontendCrashDiagnosis.diagnose(
            output: "",
            // The empty log already points to a crash, so the crash search always runs.
            reportedErrorCount: 0,
            derivedDataPath: derivedDataPath,
            windowMinutes: windowMinutes,
        ) {
            sections.append("## Compiler Crash\n\n\(crash)")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Decodes the `.dia` files under `directory` written after `cutoff`, newest first.
    static func decodeRecentDiagnostics(
        in directory: String,
        since cutoff: Date,
    ) -> [SerializedDiagnostics.Diagnostic] {
        let files = FrontendCrashDiagnosis.recentDiagnosticFiles(in: directory, since: cutoff)
        return files.prefix(maxDiagnosticFiles).flatMap { path in
            (try? SerializedDiagnostics.decode(contentsOf: path)) ?? []
        }
    }

    /// Lists the errors, then the warnings, each once.
    static func format(
        _ diagnostics: [SerializedDiagnostics.Diagnostic],
        errorsOnly: Bool,
    ) -> String {
        var seen = Set<String>()
        var errors: [String] = []
        var warnings: [String] = []

        for diagnostic in diagnostics {
            let text = diagnostic.formatted()
            guard seen.insert(text).inserted else { continue }

            switch diagnostic.severity {
                case .error, .fatal: errors.append(text)
                case .warning where !errorsOnly: warnings.append(text)
                default: continue
            }
        }

        guard !errors.isEmpty || !warnings.isEmpty else {
            return "The .dia files hold no errors or warnings."
        }
        return BuildLogDiagnosticList.format(errors: errors, warnings: warnings)
    }
}
