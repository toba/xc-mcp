import MCP
import XCMCPCore
import Foundation

public struct ResetSimLocationTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = .init(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "reset_sim_location",
            description:
                "Reset the simulated location on a simulator to default (no custom location).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ])
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        do {
            let result = try await simctlRunner.clearLocation(udid: simulator)

            if result.succeeded {
                return CallTool.Result.text(
                    "Successfully reset location on simulator '\(simulator)'")
            } else {
                throw MCPError.internalError("Failed to reset location: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
