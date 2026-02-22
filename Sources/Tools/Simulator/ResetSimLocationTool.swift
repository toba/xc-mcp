import MCP
import XCMCPCore
import Foundation

public struct ResetSimLocationTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
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

        do {
            let result = try await simctlRunner.clearLocation(udid: simulator)

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text("Successfully reset location on simulator '\(simulator)'"),
                    ],
                )
            } else {
                throw MCPError.internalError(
                    "Failed to reset location: \(result.errorOutput)",
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
