import MCP
import XCMCPCore
import Foundation

/// MCP tool for toggling the simulator's software (on-screen) keyboard via Cmd+K.
public struct ToggleSoftwareKeyboardTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "toggle_software_keyboard",
            description:
            "Toggle the simulator's on-screen software keyboard (Cmd+K). "
                + "Useful when text fields don't surface a keyboard because a hardware keyboard is connected.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID. Uses session default if not specified.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let udid = try await sessionManager.resolveSimulator(from: arguments)
        do {
            try await SimulatorKeyboardHelper.sendShortcut(
                udid: udid,
                shortcut: .softwareKeyboard,
                simctlRunner: simctlRunner,
            )
            return CallTool.Result(content: [
                .text(
                    text: "Toggled software keyboard on simulator '\(udid)'",
                    annotations: nil,
                    _meta: nil,
                ),
            ])
        } catch {
            throw error.asMCPError()
        }
    }
}
