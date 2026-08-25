import MCP
import XCMCPCore
import Foundation

/// Parses xcactivitylog files for Swift compiler crash signatures.
///
/// Searches for stack traces, signal handlers, segfaults, illegal instructions, assertion failures,
/// and other crash indicators in build logs. Returns the crash trace with the source file being
/// compiled and compiler arguments.
public struct ExtractCrashTracesTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "extract_crash_traces",
            description: "Find compiler crash signatures in Xcode build logs (xcactivitylog). "
                + "Searches for stack traces, signal handlers, segfaults, assertion failures, "
                + "and other crash indicators. Use when a build fails silently with no error output.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to search build logs for. Uses session default if not specified.",
                        ),
                    ]),
                    "max_logs": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum number of recent build logs to search. Defaults to 5.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let maxLogs = arguments.getInt("max_logs") ?? 5

        let projectRoot = try await DerivedDataLocator.findProjectRoot(
            xcodebuildRunner: xcodebuildRunner,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
        )

        let logs = try BuildLogLocator.requireLogs(inProjectRoot: projectRoot, limit: maxLogs)

        // Each log decompresses independently and runs to several megabytes, so the gunzip calls
        // run concurrently. The index restores the newest-first order the locator returned.
        let decompressed = await withTaskGroup(of: (index: Int, crash: CrashSummary?).self) {
            group in
            for (index, log) in logs.enumerated() {
                group.addTask(name: "extract_crash_traces decompress \(index)") {
                    guard let body = try? await BuildLogLocator.decompress(log) else {
                        return (index: index, crash: nil)
                    }

                    let traces = extractCrashTraces(from: body)
                    guard !traces.isEmpty else { return (index: index, crash: nil) }
                    return (
                        index: index,
                        crash: CrashSummary(logDate: log.formattedDate, traces: traces),
                    )
                }
            }
            var results: [(index: Int, crash: CrashSummary?)] = []
            results.reserveCapacity(logs.count)
            for await result in group { results.append(result) }
            return results.sorted { $0.index < $1.index }
        }

        let allCrashes = decompressed.compactMap(\.crash)

        // Format output
        var text = "## Compiler Crash Traces\n\n"
        text += "Searched \(logs.count) most recent build log(s).\n\n"

        if allCrashes.isEmpty {
            text += "No compiler crash signatures found in recent build logs.\n\n"
            text += "**Tip:** If the build failed silently, try:\n"
            text += "- `check_output_file_map` to find missing .o files\n"
            text += "- `read_serialized_diagnostics` to check .dia files\n"
            text += "- `list_build_phase_status` to see which phases completed"
        } else {
            for crash in allCrashes {
                text += "### Build Log: \(crash.logDate)\n\n"

                for (index, trace) in crash.traces.enumerated() {
                    text += "**Crash \(index + 1):** \(trace.signal)\n"
                    if let sourceFile = trace.sourceFile {
                        text += "**Source file:** \(sourceFile)\n"
                    }
                    text += "```\n\(trace.stackTrace)\n```\n\n"
                }
            }
        }

        return CallTool.Result.text(text)
    }

    // MARK: - Private

    private struct CrashTrace: Sendable {
        let signal: String
        let sourceFile: String?
        let stackTrace: String
    }

    /// Every crash found in one build log, with the log's modification time already rendered
    private struct CrashSummary: Sendable {
        let logDate: String
        let traces: [CrashTrace]
    }

    /// Crash signature patterns to search for in build log output.
    private static let crashPatterns: [(pattern: String, label: String)] = [
        ("Segmentation fault", "Segmentation fault"),
        ("Illegal instruction", "Illegal instruction"),
        ("Bus error", "Bus error"),
        ("Assertion failed", "Assertion failure"),
        ("UNREACHABLE executed", "UNREACHABLE executed"),
        ("Stack dump:", "Stack dump"),
        ("signal handler called", "Signal handler"),
        ("Please submit a bug report", "Compiler crash (bug report request)"),
        ("SIL verification failed", "SIL verification failure"),
        ("Abort trap: 6", "Abort trap"),
    ]

    private func extractCrashTraces(from log: String) -> [CrashTrace] {
        // Slices, not copies: the decompressed log runs to megabytes and every line here is only
        // read.
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        var traces: [CrashTrace] = []

        for (index, line) in lines.enumerated() {
            for (pattern, label) in Self.crashPatterns where line.contains(pattern) {
                // Extract surrounding context (up to 30 lines before, 20 after)
                let contextStart = max(0, index - 30)
                let contextEnd = min(lines.count, index + 20)
                let context = lines[contextStart..<contextEnd]

                // Try to find the source file being compiled from context
                let sourceFile = findSourceFile(in: context)

                // Extract the stack trace portion
                let stackTrace = context.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Limit stack trace length
                let truncated = stackTrace.count > 3000
                    ? String(stackTrace.prefix(3000)) + "\n... (truncated)"
                    : stackTrace

                traces.append(CrashTrace(
                    signal: label, sourceFile: sourceFile, stackTrace: truncated,
                ))
                break  // Only match one pattern per line
            }
        }

        return traces
    }

    /// Attempts to find the Swift source file being compiled when the crash occurred.
    private func findSourceFile(in context: ArraySlice<Substring>) -> String? {
        // Look for swiftc invocation lines or CompileSwift lines
        for line in context {
            // CompileSwift normal <arch> <path>
            if line.contains("CompileSwift") || line.contains("CompileC") {
                let parts = line.split(separator: " ")
                for part in parts
                    where part.hasSuffix(".swift") || part.hasSuffix(".m")
                    || part.hasSuffix(".c")
                { return String(part) }
            }
            // -primary-file /path/to/file.swift
            if line.contains("-primary-file") {
                let parts = line.split(separator: " ")
                if let idx = parts.firstIndex(where: { $0 == "-primary-file" }),
                   idx + 1 < parts.count { return String(parts[idx + 1]) }
            }
        }
        return nil
    }
}
