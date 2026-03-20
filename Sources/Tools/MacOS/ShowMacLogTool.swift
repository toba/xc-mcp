import MCP
import XCMCPCore
import Foundation

public struct ShowMacLogTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "show_mac_log",
            description:
            "Query historical macOS unified logs via `log show`. Useful for inspecting logs emitted before capture started — e.g. from a crash or app launch that already happened.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional bundle identifier to filter logs to a specific app. Uses the last component as the executable name (e.g., 'com.example.MyApp' matches process 'MyApp').",
                        ),
                    ]),
                    "process_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional process name to filter logs to a specific process.",
                        ),
                    ]),
                    "subsystem": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional OSLog subsystem to filter logs (e.g., 'com.apple.CloudKit').",
                        ),
                    ]),
                    "predicate": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional custom predicate to filter logs. Overrides bundle_id, process_name, and subsystem filters.",
                        ),
                    ]),
                    "level": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Log level to include: 'default', 'info', or 'debug'. Default is 'default' which excludes info/debug messages. Use 'info' or 'debug' to include lower-severity messages.",
                        ),
                        "enum": .array([
                            .string("default"),
                            .string("info"),
                            .string("debug"),
                        ]),
                    ]),
                    "last": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Relative time window, e.g. '5m', '1h', '30s'. Maps to `log show --last`. Defaults to '5m' if no time range is specified.",
                        ),
                    ]),
                    "start": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Absolute start time (e.g. '2024-01-15 10:30:00'). Maps to `log show --start`.",
                        ),
                    ]),
                    "end": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Absolute end time (e.g. '2024-01-15 10:35:00'). Maps to `log show --end`.",
                        ),
                    ]),
                    "tail_lines": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum number of lines to return from the end of the output. Defaults to 200.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleId = arguments.getString("bundle_id")
        let processName = arguments.getString("process_name")
        let subsystem = arguments.getString("subsystem")
        let customPredicate = arguments.getString("predicate")
        let level = arguments.getString("level")
        let last = arguments.getString("last")
        let start = arguments.getString("start")
        let end = arguments.getString("end")
        let tailLines = arguments.getInt("tail_lines") ?? 200

        do {
            var args = ["show", "--style", "compact"]

            // Add log level flags
            if let level {
                switch level {
                    case "debug":
                        args.append("--debug")
                    case "info":
                        args.append("--info")
                    default:
                        break // "default" needs no flag
                }
            }

            // Add time range — default to --last 5m if none specified
            if let last {
                args.append(contentsOf: ["--last", last])
            } else if let start {
                args.append(contentsOf: ["--start", start])
                if let end {
                    args.append(contentsOf: ["--end", end])
                }
            } else {
                args.append(contentsOf: ["--last", "5m"])
            }

            // Build predicate
            var predicate: String?

            if let customPredicate {
                predicate = customPredicate
            } else {
                var predicateParts: [String] = []

                if let bundleId {
                    if let resolved = await StartMacLogCapTool
                        .resolveExecutableName(bundleId: bundleId)
                    {
                        predicateParts.append("process == \"\(resolved)\"")
                    } else {
                        let appName = bundleId.split(separator: ".").last
                            .map(String.init) ?? bundleId
                        predicateParts.append("process ==[cd] \"\(appName)\"")
                    }
                }
                if let processName {
                    predicateParts.append("process == \"\(processName)\"")
                }
                if let subsystem {
                    predicateParts.append("subsystem == \"\(subsystem)\"")
                }

                if !predicateParts.isEmpty {
                    predicate = predicateParts.joined(separator: " AND ")
                }
            }

            if let predicate {
                args.append(contentsOf: ["--predicate", predicate])
            }

            let result = try await ProcessResult.run(
                "/usr/bin/log", arguments: args, timeout: .seconds(30),
            )

            let output = result.stdout
            let allLines = output.components(separatedBy: .newlines)
            let totalLines = allLines.count

            // Tail the output to avoid overwhelming context
            let lines: [String]
            if totalLines > tailLines {
                lines = Array(allLines.suffix(tailLines))
            } else {
                lines = allLines
            }

            var message = "## macOS Log Query\n\n"

            // Metadata header
            if let predicate {
                message += "**Predicate:** `\(predicate)`\n"
            }
            if let level, level != "default" {
                message += "**Level:** \(level)\n"
            }
            let timeRange = last ?? start ?? "last 5m"
            message += "**Time range:** \(timeRange)\n"

            if totalLines > tailLines {
                message += "**Showing:** last \(tailLines) of \(totalLines) lines\n"
            } else {
                message += "**Lines:** \(totalLines)\n"
            }

            message += "\n```\n"
            message += lines.joined(separator: "\n")
            message += "\n```"

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
