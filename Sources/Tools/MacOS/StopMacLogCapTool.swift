import MCP
import XCMCPCore
import Foundation

public struct StopMacLogCapTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "stop_mac_log_cap",
            description:
            "Stop capturing macOS logs. Can stop by process ID or kill all log stream processes. "
                + "If a process_name or bundle_id is provided and the log contains crash indicators, "
                + "automatically searches for and includes parsed crash report summaries.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the log capture process to stop.",
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional path to the log file to return the last N lines from.",
                        ),
                    ]),
                    "tail_lines": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of lines to return from the end of the log file. Defaults to 50.",
                        ),
                    ]),
                    "process_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Process name of the app being monitored. Used to auto-search crash reports if the log contains crash indicators.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app being monitored. Used to auto-search crash reports if the log contains crash indicators.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) async -> CallTool.Result {
        let pid = arguments.getInt("pid")
        let outputFile = arguments.getString("output_file")
        let tailLines = arguments.getInt("tail_lines") ?? 50
        let processName = arguments.getString("process_name")
        let bundleID = arguments.getString("bundle_id")

        await LogCapture.stopCapture(
            pid: pid,
            pkillPatterns: ["/usr/bin/log stream"],
        )

        var message = "Stopped log capture"
        if let pid {
            message += " (PID: \(pid))"
        }

        await LogCapture.appendTail(to: &message, from: outputFile, lines: tailLines)

        // Auto-search for crash reports if we have a process identifier and the
        // log output contains crash indicators (or we have no log to check)
        if processName != nil || bundleID != nil {
            let shouldSearch = Self.logContainsCrashIndicators(message) || outputFile == nil
            if shouldSearch {
                CrashReportParser.appendCrashReports(
                    to: &message, processName: processName, bundleID: bundleID,
                )
            }
        }

        return CallTool.Result(content: [.text(message)])
    }

    /// Checks whether log output contains indicators of a process crash.
    private static func logContainsCrashIndicators(_ log: String) -> Bool {
        let indicators = [
            "crashed",
            "EXC_BAD",
            "EXC_CRASH",
            "SIGABRT",
            "SIGSEGV",
            "SIGBUS",
            "SIGTRAP",
            "SIGILL",
            "dyld",
            "Symbol not found",
            "Library not loaded",
            "Termination Reason",
            "fatal error",
            "fatalError",
            "assertionFailure",
            "preconditionFailure",
        ]
        return indicators.contains { log.localizedCaseInsensitiveContains($0) }
    }
}
