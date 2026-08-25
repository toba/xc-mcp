import MCP
import XCMCPCore
import Foundation

public struct SetSimAppearanceTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = .init(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "set_sim_appearance",
            description: "Set the appearance mode (light/dark) on a simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "appearance": .object([
                        "type": .string("string"),
                        "description": .string("Appearance mode: 'light' or 'dark'."),
                        "enum": .array([.string("light"), .string("dark")]),
                    ]),
                ]),
                "required": .array([.string("appearance")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        // Get appearance
        guard let appearance = arguments.getString("appearance") else {
            throw MCPError.invalidParams("appearance is required (light or dark)")
        }

        let validAppearances = ["light", "dark"]
        guard validAppearances.contains(appearance.lowercased()) else {
            throw MCPError.invalidParams(
                "Invalid appearance '\(appearance)'. Must be 'light' or 'dark'.",
            )
        }

        do {
            let result = try await simctlRunner.setAppearance(
                udid: simulator, appearance: appearance.lowercased(),
            )

            if result.succeeded {
                return CallTool.Result.text(
                    "Successfully set appearance to '\(appearance)' on simulator '\(simulator)'")
            } else {
                throw MCPError.internalError("Failed to set appearance: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
