import MCP
import XCMCPCore
import Foundation

public struct InteractUITreeTool: Sendable {
    private let interactRunner: InteractRunner

    public init(interactRunner: InteractRunner) {
        self.interactRunner = interactRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "interact_ui_tree",
            description:
            "Get the UI element tree of a macOS application using the Accessibility API. "
                + "Returns a hierarchical tree of UI elements with assigned IDs for use with other interact_ tools. "
                +
                "Requires Accessibility permission in System Settings > Privacy & Security > Accessibility.",
            inputSchema: .object(
                [
                    "type": .string("object"),
                    "properties": .object(
                        InteractRunner.appResolutionSchemaProperties.merging([
                            "max_depth": .object([
                                "type": .string("integer"),
                                "description": .string(
                                    "Maximum depth to traverse the element tree. Default 3.",
                                ),
                            ]),
                        ]) { _, new in new },
                    ),
                    "required": .array([]),
                ],
            ),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid = try interactRunner.resolveAppFromArguments(arguments)
        let maxDepth = arguments.getInt("max_depth") ?? 3

        let tree = try interactRunner.getUITree(pid: pid, maxDepth: maxDepth)

        // Cache the AXUIElement refs
        let sendableElements = tree.map(\.1)
        await InteractSessionManager.shared.cacheElements(pid: pid, elements: sendableElements)

        // Format output
        var lines: [String] = []
        lines.append("UI Tree for PID \(pid) (depth=\(maxDepth), \(tree.count) elements):")
        lines.append("")
        for (element, _) in tree {
            lines.append(element.summary())
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
