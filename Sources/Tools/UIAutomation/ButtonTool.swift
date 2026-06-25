import MCP
import XCMCPCore
import Foundation

public struct ButtonTool: Sendable {
    private let uiInput: SimulatorUIInput
    private let sessionManager: SessionManager

    public init(uiInput: SimulatorUIInput = .init(), sessionManager: SessionManager) {
        self.uiInput = uiInput
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "button",
            description:
                "Press a hardware button on a booted simulator via the Simulator Device menu.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "button_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Button to press: 'home', 'lock', 'siri', 'shake', 'screenshot', "
                                + "'rotate_left', 'rotate_right'.",
                        ),
                    ]),
                ]),
                "required": .array([.string("button_name")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        guard case let .string(buttonName) = arguments["button_name"] else {
            throw MCPError.invalidParams("button_name is required")
        }

        do {
            try await uiInput.pressButton(simulator: simulator, button: buttonName)
            return CallTool.Result(content: [
                .text(
                    text: "Pressed button '\(buttonName)' on simulator '\(simulator)'",
                    annotations: nil, _meta: nil)
            ],)
        } catch {
            throw try error.asMCPError()
        }
    }
}
