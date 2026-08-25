import MCP
import XCMCPCore
import Foundation

public struct TypeTextTool: Sendable {
    private let uiInput: SimulatorUIInput
    private let sessionManager: SessionManager

    public init(uiInput: SimulatorUIInput = .init(), sessionManager: SessionManager) {
        self.uiInput = uiInput
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "type_text",
            description:
                "Type text into the currently focused field on a booted simulator. Sends host keystrokes "
                + "to the Simulator window, so a text field must be focused (tap it first) and the "
                + "hardware keyboard connected (the default; see toggle_hardware_keyboard).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "text": .object([
                        "type": .string("string"), "description": .string("Text to type."),
                    ]),
                ]),
                "required": .array([.string("text")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        let text = try arguments.getRequiredString("text")

        do {
            try await uiInput.typeText(simulator: simulator, text: text)
            let truncatedText = text.count > 20 ? String(text.prefix(20)) + "..." : text
            return CallTool.Result.text("Typed '\(truncatedText)' on simulator '\(simulator)'")
        } catch {
            throw try error.asMCPError()
        }
    }
}
