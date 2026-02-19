import Foundation
import MCP
import XCMCPCore

public struct EraseSimTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "erase_sims",
            description:
                "Erase all content and settings from a simulator, restoring it to factory state.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "all": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, erases all simulators. Use with caution."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let eraseAll = arguments.getBool("all")

        if eraseAll {
            // Erase all simulators
            do {
                let result = try await simctlRunner.eraseAll()

                if result.succeeded {
                    return CallTool.Result(
                        content: [.text("Successfully erased all simulators")]
                    )
                } else {
                    throw MCPError.internalError(
                        "Failed to erase simulators: \(result.errorOutput)"
                    )
                }
            } catch {
                throw error.asMCPError()
            }
        }

        // Erase specific simulator
        let simulator: String
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else if let sessionSimulator = await sessionManager.simulatorUDID {
            simulator = sessionSimulator
        } else {
            throw MCPError.invalidParams(
                "simulator is required. Set it with set_session_defaults or pass it directly, or use 'all: true' to erase all."
            )
        }

        do {
            let result = try await simctlRunner.erase(udid: simulator)

            if result.succeeded {
                return CallTool.Result(
                    content: [.text("Successfully erased simulator '\(simulator)'")]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to erase simulator: \(result.errorOutput)"
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
