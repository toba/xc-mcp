import MCP
import XCMCPCore
import Foundation

public struct StartSimLogCapTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "start_sim_log_cap",
            description:
            "Start capturing logs from a simulator. Logs are written to a file and can be stopped with stop_sim_log_cap.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to write logs to. Defaults to /tmp/sim_log_<udid>.log",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional bundle identifier to filter logs to a specific app.",
                        ),
                    ]),
                    "predicate": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional predicate to filter logs (e.g., 'subsystem == \"com.apple.example\"').",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get simulator
        let simulator: String
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else if let sessionSimulator = await sessionManager.simulatorUDID {
            simulator = sessionSimulator
        } else {
            throw MCPError.invalidParams(
                "simulator is required. Set it with set_session_defaults or pass it directly.",
            )
        }

        // Get output file
        let outputFile: String
        if case let .string(value) = arguments["output_file"] {
            outputFile = value
        } else {
            outputFile = "/tmp/sim_log_\(simulator).log"
        }

        // Get optional bundle_id filter
        let bundleId = arguments.getString("bundle_id")

        // Get optional predicate
        let predicate = arguments.getString("predicate")

        do {
            var args = ["simctl", "spawn", simulator, "log", "stream", "--style", "compact"]

            if let bundleId {
                args.append(contentsOf: [
                    "--predicate", "processImagePath CONTAINS \"\(bundleId)\"",
                ])
            } else if let predicate {
                args.append(contentsOf: ["--predicate", predicate])
            }

            let pid = try LogCapture.launchStreamProcess(
                executable: "/usr/bin/xcrun", arguments: args, outputFile: outputFile,
            )

            var message = "Started log capture for simulator '\(simulator)'\n"
            message += "Output file: \(outputFile)\n"
            message += "Process ID: \(pid)\n"
            if let bundleId {
                message += "Filtering for bundle: \(bundleId)\n"
            }
            message += "\nUse stop_sim_log_cap to stop the capture."

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
