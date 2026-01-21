import Foundation
import XCMCPCore
import MCP

public struct ButtonTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "button",
            description:
                "Simulate pressing a hardware button on a simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "button_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Button to press: 'home', 'lock', 'volumeUp', 'volumeDown', 'siri', 'screenshot'."
                        ),
                    ]),
                ]),
                "required": .array([.string("button_name")]),
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

        // Get button name
        guard case let .string(buttonName) = arguments["button_name"] else {
            throw MCPError.invalidParams("button_name is required")
        }

        let validButtons = ["home", "lock", "volumeUp", "volumeDown", "siri", "screenshot"]
        let normalizedButton =
            buttonName.lowercased() == "volumeup"
            ? "volumeUp"
            : (buttonName.lowercased() == "volumedown" ? "volumeDown" : buttonName.lowercased())

        guard
            validButtons.contains(normalizedButton)
                || validButtons.contains(normalizedButton.lowercased())
        else {
            throw MCPError.invalidParams(
                "Invalid button '\(buttonName)'. Valid buttons: \(validButtons.joined(separator: ", "))"
            )
        }

        do {
            let result = try await simctlRunner.run(
                arguments: ["io", simulator, "button", normalizedButton])

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Pressed button '\(buttonName)' on simulator '\(simulator)'"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to press button: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to press button: \(error.localizedDescription)")
        }
    }
}
