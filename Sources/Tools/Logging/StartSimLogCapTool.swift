import MCP
import XCMCPCore
import Foundation

public struct StartSimLogCapTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = .init(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
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
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        // Get output file
        let outputFile = arguments.getString("output_file") ?? "/tmp/sim_log_\(simulator).log"

        // Get optional bundle_id filter
        let bundleID = arguments.getString("bundle_id")

        // Get optional predicate
        let predicate = arguments.getString("predicate")

        do {
            if let bundleID { try PredicateFilterValidator.validate(bundleID, field: "bundle_id") }

            var args = ["simctl", "spawn", simulator, "log", "stream", "--style", "compact"]

            if let bundleID {
                args.append(contentsOf: [
                    "--predicate", "processImagePath CONTAINS \"\(bundleID)\"",
                ])
            } else if let predicate { args.append(contentsOf: ["--predicate", predicate]) }

            let pid = try LogCapture.launchStreamProcess(
                executable: "/usr/bin/xcrun", arguments: args, outputFile: outputFile,
            )

            var message = "Started log capture for simulator '\(simulator)'\n"
            message += "Output file: \(outputFile)\n"
            message += "Process ID: \(pid)\n"
            if let bundleID { message += "Filtering for bundle: \(bundleID)\n" }
            message += "\nUse stop_sim_log_cap to stop the capture."

            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }
}
