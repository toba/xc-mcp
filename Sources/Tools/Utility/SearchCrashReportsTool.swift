import MCP
import XCMCPCore
import Foundation

public struct SearchCrashReportsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "search_crash_reports",
            description:
            "Search ~/Library/Logs/DiagnosticReports/ for recent .ips crash reports, or read a specific report by path. "
                + "Returns exception type, signal, termination reason, crashing thread stack trace, and details. "
                + "Useful after an app crash to diagnose the cause without opening Console.app.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "process_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Process name to filter by (e.g., 'ThesisApp'). "
                                +
                                "Matched case-insensitively against filename and crash report contents.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier to filter by (e.g., 'com.example.MyApp').",
                        ),
                    ]),
                    "minutes": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Only include reports from the last N minutes. Defaults to 5.",
                        ),
                    ]),
                    "report_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a specific .ips crash report file to read. When provided, skips the search and parses this file directly. The path is returned by a previous search_crash_reports call.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) -> CallTool.Result {
        // Direct read mode: parse a specific crash report file
        if let reportPath = arguments.getString("report_path") {
            guard let summary = CrashReportParser.parse(at: reportPath) else {
                return CallTool.Result(
                    content: [.text("Could not parse crash report at: \(reportPath)")],
                    isError: true,
                )
            }
            var output = "File: \(reportPath)\n"
            output += summary.formatted()
            return CallTool.Result(content: [.text(output)])
        }

        // Search mode
        let processName = arguments.getString("process_name")
        let bundleID = arguments.getString("bundle_id")
        let minutes = arguments.getInt("minutes") ?? 5

        let results = CrashReportParser.search(
            processName: processName,
            bundleID: bundleID,
            minutes: minutes,
        )

        if results.isEmpty {
            var message = "No crash reports found in the last \(minutes) minute\(minutes == 1 ? "" : "s")"
            if let processName {
                message += " for process '\(processName)'"
            }
            if let bundleID {
                message += " with bundle ID '\(bundleID)'"
            }
            message += ".\n\nSearched: \(CrashReportParser.diagnosticReportsDir)"
            return CallTool.Result(content: [.text(message)])
        }

        var output = "Found \(results.count) crash report\(results.count == 1 ? "" : "s"):\n"

        for (i, result) in results.enumerated() {
            if i > 0 {
                output += "\n" + String(repeating: "─", count: 60) + "\n"
            }
            output += "\nFile: \(result.path)\n"
            output += result.summary.formatted()
            output += "\n"
        }

        output += "\nUse report_path to read a specific report again without re-searching."

        return CallTool.Result(content: [.text(output)])
    }
}
