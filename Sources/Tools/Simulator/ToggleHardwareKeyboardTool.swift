import MCP
import XCMCPCore
import Foundation

/// MCP tool for toggling the simulator's "Connect Hardware Keyboard" setting via Cmd+Shift+K.
public struct ToggleHardwareKeyboardTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "toggle_hardware_keyboard",
            description:
            "Toggle the simulator's 'Connect Hardware Keyboard' setting (Cmd+Shift+K). "
                + "Disconnect the hardware keyboard to reveal the on-screen software keyboard during UI automation.",
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
                shortcut: .connectHardwareKeyboard,
                simctlRunner: simctlRunner,
            )
            return CallTool.Result(content: [
                .text(
                    text: "Toggled hardware keyboard connection on simulator '\(udid)'",
                    annotations: nil,
                    _meta: nil,
                ),
            ])
        } catch {
            throw try error.asMCPError()
        }
    }
}
