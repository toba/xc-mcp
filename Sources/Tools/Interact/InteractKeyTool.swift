import MCP
import XCMCPCore
import Foundation

public struct InteractKeyTool: Sendable {
    private let interactRunner: InteractRunner

    public init(interactRunner: InteractRunner) { self.interactRunner = interactRunner }

    public func tool() -> Tool {
        .init(
            name: "interact_key",
            description:
                "Send a keyboard event via CGEvent. Supports key names like 'return', 'tab', 'escape', "
                + "'space', 'a'-'z', '0'-'9', 'f1'-'f12', 'up', 'down', 'left', 'right', 'delete', etc. "
                + "Optional modifier keys: 'command', 'shift', 'option', 'control'.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(InteractRunner.appResolutionSchemaProperties.merging([
                    "key": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Key name to press (e.g., 'return', 'a', 'f5', 'space', 'tab').",
                        ),
                    ]),
                    "modifiers": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Modifier keys to hold during the key press (e.g., ['command', 'shift']).",
                        ),
                    ]),
                ]) { _, new in new }),
                "required": .array([.string("key")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let key = try arguments.getRequiredString("key")
        let modifiers = arguments.getStringArray("modifiers")

        try interactRunner.sendKeyEvent(keyName: key, modifiers: modifiers)

        var desc = "Sent key: \(key)"
        if !modifiers.isEmpty { desc += " with modifiers: \(modifiers.joined(separator: "+"))" }

        // CGEvents are posted globally; only snapshot when a target app is identified.
        if arguments.getInt("pid") != nil || arguments.getString("bundle_id") != nil
            || arguments.getString("app_name") != nil
        {
            let pid = try interactRunner.resolveAppFromArguments(arguments)
            let snapshot = try await InteractPostAction.settledSnapshot(
                runner: interactRunner, pid: pid,
            )
            desc += "\n\(snapshot)"
        }
        return CallTool.Result(content: [.text(text: desc, annotations: nil, _meta: nil)])
    }
}
