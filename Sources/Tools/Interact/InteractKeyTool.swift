import Foundation
import MCP
import XCMCPCore

public struct InteractKeyTool: Sendable {
  private let interactRunner: InteractRunner

  public init(interactRunner: InteractRunner) {
    self.interactRunner = interactRunner
  }

  public func tool() -> Tool {
    Tool(
      name: "interact_key",
      description:
        "Send a keyboard event via CGEvent. Supports key names like 'return', 'tab', 'escape', "
        + "'space', 'a'-'z', '0'-'9', 'f1'-'f12', 'up', 'down', 'left', 'right', 'delete', etc. "
        + "Optional modifier keys: 'command', 'shift', 'option', 'control'.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
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
        ]),
        "required": .array([.string("key")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) throws -> CallTool.Result {
    let key = try arguments.getRequiredString("key")
    let modifiers = arguments.getStringArray("modifiers")

    try interactRunner.sendKeyEvent(keyName: key, modifiers: modifiers)

    var desc = "Sent key: \(key)"
    if !modifiers.isEmpty {
      desc += " with modifiers: \(modifiers.joined(separator: "+"))"
    }
    return CallTool.Result(content: [.text(desc)])
  }
}
