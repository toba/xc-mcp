import ApplicationServices
import Foundation
import MCP
import XCMCPCore

public struct InteractSetValueTool: Sendable {
  private let interactRunner: InteractRunner

  public init(interactRunner: InteractRunner) {
    self.interactRunner = interactRunner
  }

  public func tool() -> Tool {
    Tool(
      name: "interact_set_value",
      description:
        "Set the value of a UI element (text field, checkbox, etc.) in a macOS application. "
        + "Use element_id from interact_ui_tree.",
      inputSchema: .object(
        [
          "type": .string("object"),
          "properties": .object(
            InteractRunner.appResolutionSchemaProperties.merging([
              "element_id": .object([
                "type": .string("integer"),
                "description": .string(
                  "Element ID from interact_ui_tree.",
                ),
              ]),
              "value": .object([
                "type": .string("string"),
                "description": .string(
                  "The value to set on the element.",
                ),
              ]),
            ]) { _, new in new },
          ),
          "required": .array([.string("element_id"), .string("value")]),
        ],
      ),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let pid = try interactRunner.resolveAppFromArguments(arguments)
    try interactRunner.ensureAccessibility()

    guard let elementId = arguments.getInt("element_id") else {
      throw MCPError.invalidParams("element_id is required")
    }
    let value = try arguments.getRequiredString("value")

    guard
      let cached = await InteractSessionManager.shared.getElement(
        pid: pid, elementId: elementId,
      )
    else {
      throw InteractError.elementNotFound(elementId)
    }

    try interactRunner.setValue(value, on: cached.element)

    let info = interactRunner.getAttributes(from: cached.element)
    let desc = info.role ?? "element"
    return CallTool.Result(
      content: [.text("Set value on \(desc) (id=\(elementId)) to \"\(value)\".")],
    )
  }
}
