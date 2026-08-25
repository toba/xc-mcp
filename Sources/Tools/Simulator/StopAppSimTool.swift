import MCP
import XCMCPCore
import Foundation

public struct StopAppSimTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = .init(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "stop_app_sim",
            description: "Stop (terminate) a running app on a simulator by its bundle identifier.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app to stop (e.g., 'com.example.MyApp').",
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                ]),
                "required": .array([.string("bundle_id")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleID = try arguments.getRequiredString("bundle_id")
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        do {
            let result = try await simctlRunner.terminate(udid: simulator, bundleID: bundleID)

            if result.succeeded {
                return CallTool.Result.text(
                    "Successfully stopped '\(bundleID)' on simulator '\(simulator)'")
            } else if result.stderr.contains("No matching processes") {
                return CallTool.Result.text(
                    "App '\(bundleID)' was not running on simulator '\(simulator)'")
            } else {
                throw MCPError.internalError("Failed to stop app: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
