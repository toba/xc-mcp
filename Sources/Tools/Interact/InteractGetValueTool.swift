import ApplicationServices
import Foundation
import MCP
import XCMCPCore

public struct InteractGetValueTool: Sendable {
  private let interactRunner: InteractRunner

  public init(interactRunner: InteractRunner) {
    self.interactRunner = interactRunner
  }

  public func tool() -> Tool {
    Tool(
      name: "interact_get_value",
      description:
        "Read all attributes of a UI element by ID. Returns role, title, value, identifier, "
        + "position, size, enabled state, focused state, and available actions.",
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
              ])
            ]) { _, new in new },
          ),
          "required": .array([.string("element_id")]),
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

    guard
      let cached = await InteractSessionManager.shared.getElement(
        pid: pid, elementId: elementId,
      )
    else {
      throw InteractError.elementNotFound(elementId)
    }

    let info = interactRunner.getAttributes(from: cached.element, id: elementId)

    var lines: [String] = []
    lines.append("Element \(elementId):")
    if let role = info.role { lines.append("  Role: \(role)") }
    if let subrole = info.subrole { lines.append("  Subrole: \(subrole)") }
    if let title = info.title { lines.append("  Title: \(title)") }
    if let value = info.value { lines.append("  Value: \(value)") }
    if let identifier = info.identifier { lines.append("  Identifier: \(identifier)") }
    if let roleDesc = info.roleDescription { lines.append("  Role Description: \(roleDesc)") }
    if let pos = info.position { lines.append("  Position: (\(pos.x), \(pos.y))") }
    if let size = info.size { lines.append("  Size: \(size.width) x \(size.height)") }
    lines.append("  Enabled: \(info.enabled)")
    lines.append("  Focused: \(info.focused)")
    if !info.actions.isEmpty {
      lines.append("  Actions: \(info.actions.joined(separator: ", "))")
    }
    lines.append("  Children: \(info.childCount)")

    return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
  }
}
