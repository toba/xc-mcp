import Foundation
import MCP
import XCMCPCore

public struct KeyPressTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "key_press",
            description:
                "Simulate pressing a hardware key on a simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Key to press. Common keys: 'home', 'volumeUp', 'volumeDown', 'lock', 'return', 'escape', 'delete', 'space', 'tab', or any single character."
                        ),
                    ]),
                ]),
                "required": .array([.string("key")]),
            ])
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
                "simulator is required. Set it with set_session_defaults or pass it directly.")
        }

        // Get key
        guard case let .string(key) = arguments["key"] else {
            throw MCPError.invalidParams("key is required")
        }

        do {
            // Map common key names to simctl keyboard commands
            let result: SimctlResult
            switch key.lowercased() {
            case "home":
                result = try await simctlRunner.run(arguments: ["io", simulator, "button", "home"])
            case "lock", "power":
                result = try await simctlRunner.run(arguments: ["io", simulator, "button", "lock"])
            case "volumeup":
                result = try await simctlRunner.run(
                    arguments: ["io", simulator, "button", "volumeUp"])
            case "volumedown":
                result = try await simctlRunner.run(
                    arguments: ["io", simulator, "button", "volumeDown"])
            case "siri":
                result = try await simctlRunner.run(arguments: ["io", simulator, "button", "siri"])
            default:
                // For other keys, use keyboard key command
                result = try await simctlRunner.run(
                    arguments: ["io", simulator, "keyboard", "key", key])
            }

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Pressed key '\(key)' on simulator '\(simulator)'"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to press key: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to press key: \(error.localizedDescription)")
        }
    }
}
