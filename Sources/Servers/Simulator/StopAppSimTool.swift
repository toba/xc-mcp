import Foundation
import MCP
import XCMCPCore

public struct StopAppSimTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "stop_app_sim",
            description: "Stop (terminate) a running app on a simulator by its bundle identifier.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app to stop (e.g., 'com.example.MyApp')."),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                ]),
                "required": .array([.string("bundle_id")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleId = try arguments.getRequiredString("bundle_id")
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        do {
            let result = try await simctlRunner.terminate(udid: simulator, bundleId: bundleId)

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text("Successfully stopped '\(bundleId)' on simulator '\(simulator)'")
                    ]
                )
            } else if result.stderr.contains("No matching processes") {
                return CallTool.Result(
                    content: [
                        .text("App '\(bundleId)' was not running on simulator '\(simulator)'")
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to stop app: \(result.stderr.isEmpty ? result.stdout : result.stderr)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to stop app: \(error.localizedDescription)")
        }
    }
}
