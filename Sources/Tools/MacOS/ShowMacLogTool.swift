import MCP
import XCMCPCore
import Foundation

public struct ShowMacLogTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) { self.sessionManager = sessionManager }

    public func tool() -> Tool {
        .init(
            name: "show_mac_log",
            description:
                "Query historical macOS unified logs via `log show`. Useful for inspecting logs emitted before capture started — e.g. from a crash or app launch that already happened.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(UnifiedLogQuery.schemaProperties.merging([
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
                ]) { _, new in new },
                ),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let last = arguments.getString("last")
        let start = arguments.getString("start")
        let end = arguments.getString("end")
        let tailLines = arguments.getInt("tail_lines") ?? 200

        do {
            let query = try UnifiedLogQuery(arguments: arguments)

            // Default to --last 5m when the caller names no time range
            let timeRangeArgs: [String] =
                if let last {
                    ["--last", last]
                } else if let start {
                    ["--start", start] + (end.map { ["--end", $0] } ?? [])
                } else {
                    ["--last", "5m"]
                }

            let predicate = await query.resolvedPredicate()
            let args = query.commandArguments(
                subcommand: "show", predicate: predicate, extra: timeRangeArgs,
            )

            let result = try await ProcessResult.run(
                "/usr/bin/log", arguments: args, timeout: .seconds(30),
            )

            let output = result.stdout
            let allLines = output.components(separatedBy: .newlines)
            let totalLines = allLines.count

            // Tail the output to avoid overwhelming context
            let lines: [String]
            lines = totalLines > tailLines
                ? Array(allLines.suffix(tailLines))
                : allLines

            var message = "## macOS Log Query\n\n"

            // Metadata header
            if let predicate { message += "**Predicate:** `\(predicate)`\n" }
            if let level = query.level, level != .default {
                message += "**Level:** \(level.rawValue)\n"
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

            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }
}
