import ApplicationServices
import Foundation
import MCP
import XCMCPCore

public struct InteractClickTool: Sendable {
    private let interactRunner: InteractRunner

    public init(interactRunner: InteractRunner) {
        self.interactRunner = interactRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "interact_click",
            description:
                "Click a UI element in a macOS application. Specify either element_id (from interact_ui_tree) "
                + "or role+title to find and click an element. Performs the AXPress action.",
            inputSchema: .object(
                [
                    "type": .string("object"),
                    "properties": .object(
                        InteractRunner.appResolutionSchemaProperties.merging([
                            "element_id": .object([
                                "type": .string("integer"),
                                "description": .string(
                                    "Element ID from interact_ui_tree to click."
                                ),
                            ]),
                            "role": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "AX role to search for (e.g., 'AXButton'). Used with title for query-based click."
                                ),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "Title to search for. Used with role for query-based click."
                                ),
                            ]),
                        ]) { _, new in new }
                    ),
                    "required": .array([]),
                ]
            )
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid = try interactRunner.resolveAppFromArguments(arguments)
        try interactRunner.ensureAccessibility()

        let element: AXUIElement

        if let elementId = arguments.getInt("element_id") {
            // Look up from cache
            guard
                let cached = await InteractSessionManager.shared.getElement(
                    pid: pid, elementId: elementId
                )
            else {
                throw InteractError.elementNotFound(elementId)
            }
            element = cached.element
        } else {
            // Search by role/title
            let role = arguments.getString("role")
            let title = arguments.getString("title")
            guard role != nil || title != nil else {
                throw MCPError.invalidParams(
                    "Either element_id or at least one of role/title is required."
                )
            }
            let matches = try interactRunner.findElements(
                pid: pid, role: role, title: title
            )
            guard let first = matches.first else {
                var query: [String] = []
                if let role { query.append("role=\(role)") }
                if let title { query.append("title=\(title)") }
                throw InteractError.elementNotFoundByQuery(query.joined(separator: ", "))
            }
            element = first.1.element
        }

        try interactRunner.performAction(kAXPressAction, on: element)

        let info = interactRunner.getAttributes(from: element)
        let desc = info.title ?? info.role ?? "element"
        return CallTool.Result(content: [.text("Clicked \(desc) successfully.")])
    }
}
