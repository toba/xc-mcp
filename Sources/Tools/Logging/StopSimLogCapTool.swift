import Foundation
import XCMCPCore
import MCP

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
                            "Process ID of the log capture process to stop."),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. If specified, stops all log capture for this simulator."
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional path to the log file to return the last N lines from."),
                    ]),
                    "tail_lines": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of lines to return from the end of the log file. Defaults to 50."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid: Int?
        if case let .int(value) = arguments["pid"] {
            pid = value
        } else {
            pid = nil
        }

        let simulator: String?
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else {
            simulator = await sessionManager.simulatorUDID
        }

        let outputFile: String?
        if case let .string(value) = arguments["output_file"] {
            outputFile = value
        } else if let sim = simulator {
            outputFile = "/tmp/sim_log_\(sim).log"
        } else {
            outputFile = nil
        }

        let tailLines: Int
        if case let .int(value) = arguments["tail_lines"] {
            tailLines = value
        } else {
            tailLines = 50
        }

        // Must have either pid or simulator
        if pid == nil && simulator == nil {
            throw MCPError.invalidParams(
                "Either pid or simulator is required to stop log capture.")
        }

        do {
            if let pid {
                // Kill specific process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["\(pid)"]

                try process.run()
                process.waitUntilExit()

            } else if let simulator {
                // Find and kill all log stream processes for this simulator
                // Use pkill to kill processes matching the pattern
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                process.arguments = ["-f", "simctl spawn \(simulator) log stream"]

                try process.run()
                process.waitUntilExit()

                // Also try the alternate pattern
                let process2 = Process()
                process2.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                process2.arguments = ["-f", "xcrun simctl.*\(simulator).*log stream"]

                try process2.run()
                process2.waitUntilExit()
            }

            var message = "Stopped log capture"
            if let pid {
                message += " (PID: \(pid))"
            } else if let simulator {
                message += " for simulator '\(simulator)'"
            }

            // Read tail of log file if available
            if let outputFile, FileManager.default.fileExists(atPath: outputFile) {
                let tailProcess = Process()
                tailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
                tailProcess.arguments = ["-n", "\(tailLines)", outputFile]

                let pipe = Pipe()
                tailProcess.standardOutput = pipe

                try tailProcess.run()
                tailProcess.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let tailOutput = String(data: data, encoding: .utf8), !tailOutput.isEmpty {
                    message += "\n\nLast \(tailLines) lines of log:\n"
                    message += String(repeating: "-", count: 50) + "\n"
                    message += tailOutput
                }
            }

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to stop log capture: \(error.localizedDescription)")
        }
    }
}
