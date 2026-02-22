import MCP
import XCMCPCore
import Foundation

public struct StopSimLogCapTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "stop_sim_log_cap",
            description:
            "Stop capturing logs from a simulator. Can stop by process ID or kill all log stream processes for a simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the log capture process to stop.",
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. If specified, stops all log capture for this simulator.",
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
        let simulator: String?
        if let explicit = arguments.getString("simulator") {
            simulator = explicit
        } else {
            simulator = await sessionManager.simulatorUDID
        }
        let outputFile =
            arguments.getString("output_file")
                ?? simulator.map { "/tmp/sim_log_\($0).log" }
        let tailLines = arguments.getInt("tail_lines") ?? 50

        // Must have either pid or simulator
        if pid == nil, simulator == nil {
            throw MCPError.invalidParams(
                "Either pid or simulator is required to stop log capture.",
            )
        }

        do {
            if let pid {
                try await ProcessResult.run("/bin/kill", arguments: ["\(pid)"]).ignore()
            } else if let simulator {
                _ = try? await ProcessResult.run(
                    "/usr/bin/pkill",
                    arguments: ["-f", "simctl spawn \(simulator) log stream"],
                )
                _ = try? await ProcessResult.run(
                    "/usr/bin/pkill",
                    arguments: ["-f", "xcrun simctl.*\(simulator).*log stream"],
                )
            }

            var message = "Stopped log capture"
            if let pid {
                message += " (PID: \(pid))"
            } else if let simulator {
                message += " for simulator '\(simulator)'"
            }

            await LogCapture.appendTail(to: &message, from: outputFile, lines: tailLines)

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
