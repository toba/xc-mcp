import MCP
import XCMCPCore
import Foundation

/// Parses xcactivitylog files for Swift compiler crash signatures.
///
/// Searches for stack traces, signal handlers, segfaults, illegal instructions,
/// assertion failures, and other crash indicators in build logs. Returns the
/// crash trace with the source file being compiled and compiler arguments.
public struct ExtractCrashTracesTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "extract_crash_traces",
            description:
            "Find compiler crash signatures in Xcode build logs (xcactivitylog). "
                + "Searches for stack traces, signal handlers, segfaults, assertion failures, "
                +
                "and other crash indicators. Use when a build fails silently with no error output.",
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

        let logsDir = URL(fileURLWithPath: projectRoot).appendingPathComponent("Logs/Build").path
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: logsDir) else {
            throw MCPError.internalError("No build logs found at \(logsDir)")
        }

        let logs = entries.filter { $0.hasSuffix(".xcactivitylog") }
            .compactMap { name -> (path: String, date: Date)? in
                let path = (logsDir as NSString).appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let date = attrs[.modificationDate] as? Date
                else { return nil }
                return (path, date)
            }
            .sorted { $0.date > $1.date }
            .prefix(maxLogs)

        guard !logs.isEmpty else {
            throw MCPError.internalError("No build logs found in \(logsDir)")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var allCrashes: [(logDate: String, traces: [CrashTrace])] = []

        for log in logs {
            let decompressed: String
            do {
                let result = try await ProcessResult.run(
                    "/usr/bin/gunzip", arguments: ["-c", log.path], timeout: .seconds(30),
                )
                decompressed = result.stdout
            } catch {
                continue
            }

            let traces = extractCrashTraces(from: decompressed)
            if !traces.isEmpty {
                allCrashes.append(
                    (logDate: dateFormatter.string(from: log.date), traces: traces),
                )
            }
        }

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

        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - Private

    private struct CrashTrace {
        let signal: String
        let sourceFile: String?
        let stackTrace: String
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
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var traces: [CrashTrace] = []

        for (index, line) in lines.enumerated() {
            for (pattern, label) in Self.crashPatterns {
                guard line.contains(pattern) else { continue }

                // Extract surrounding context (up to 30 lines before, 20 after)
                let contextStart = max(0, index - 30)
                let contextEnd = min(lines.count, index + 20)
                let context = Array(lines[contextStart ..< contextEnd])

                // Try to find the source file being compiled from context
                let sourceFile = findSourceFile(in: context)

                // Extract the stack trace portion
                let stackTrace = context.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Limit stack trace length
                let truncated =
                    stackTrace.count > 3000
                        ? String(stackTrace.prefix(3000)) + "\n... (truncated)"
                        : stackTrace

                traces.append(
                    CrashTrace(
                        signal: label,
                        sourceFile: sourceFile,
                        stackTrace: truncated,
                    ),
                )
                break // Only match one pattern per line
            }
        }

        return traces
    }

    /// Attempts to find the Swift source file being compiled when the crash occurred.
    private func findSourceFile(in context: [String]) -> String? {
        // Look for swiftc invocation lines or CompileSwift lines
        for line in context {
            // CompileSwift normal <arch> <path>
            if line.contains("CompileSwift") || line.contains("CompileC") {
                let parts = line.split(separator: " ")
                for part in parts where part.hasSuffix(".swift") || part.hasSuffix(".m")
                    || part.hasSuffix(".c")
                {
                    return String(part)
                }
            }
            // -primary-file /path/to/file.swift
            if line.contains("-primary-file") {
                let parts = line.split(separator: " ")
                if let idx = parts.firstIndex(where: { $0 == "-primary-file" }),
                   idx + 1 < parts.count
                {
                    return String(parts[idx + 1])
                }
            }
        }
        return nil
    }
}
