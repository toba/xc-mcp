import MCP
import XCMCPCore
import Foundation

public struct KeyPressTool: Sendable {
    private let uiInput: SimulatorUIInput
    private let sessionManager: SessionManager

    public init(uiInput: SimulatorUIInput = .init(), sessionManager: SessionManager) {
        self.uiInput = uiInput
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "key_press",
            description:
                "Press a key on a booted simulator. Hardware-button names (home/lock/siri/shake) drive "
                + "the Simulator Device menu; other keys (return/escape/delete/space/tab/arrows or a "
                + "single character) are sent as host keystrokes to the focused Simulator window.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Key to press. Hardware buttons: 'home', 'lock', 'siri', 'shake'. Keys: 'return', 'escape', 'delete', 'space', 'tab', arrows, or any single character.",
                        ),
                    ]),
                ]),
                "required": .array([.string("key")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        guard case let .string(key) = arguments["key"] else {
            throw MCPError.invalidParams("key is required")
        }

        do {
            try await uiInput.pressKey(simulator: simulator, key: key)
            return CallTool.Result(content: [
                .text(
                    text: "Pressed key '\(key)' on simulator '\(simulator)'",
                    annotations: nil, _meta: nil)
            ],)
        } catch {
            throw try error.asMCPError()
        }
    }
}
