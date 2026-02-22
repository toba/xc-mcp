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
            "Stop capturing macOS logs. Can stop by process ID or kill all log stream processes.",
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
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid = arguments.getInt("pid")
        let outputFile = arguments.getString("output_file")
        let tailLines = arguments.getInt("tail_lines") ?? 50

        do {
            if let pid {
                try await ProcessResult.run("/bin/kill", arguments: ["\(pid)"]).ignore()
            } else {
                _ = try? await ProcessResult.run(
                    "/usr/bin/pkill", arguments: ["-f", "/usr/bin/log stream"],
                )
            }

            var message = "Stopped log capture"
            if let pid {
                message += " (PID: \(pid))"
            }

            await LogCapture.appendTail(to: &message, from: outputFile, lines: tailLines)

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
