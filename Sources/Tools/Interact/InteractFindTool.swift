import MCP
import XCMCPCore
import Foundation

public struct InteractFindTool: Sendable {
    private let interactRunner: InteractRunner

    public init(interactRunner: InteractRunner) {
        self.interactRunner = interactRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "interact_find",
            description:
            "Search for UI elements by role, title, identifier, or value with substring matching. "
                + "Returns matching elements and caches the full tree for subsequent interact_ calls. "
                + "Default search depth is 10.",
            inputSchema: .object(
                [
                    "type": .string("object"),
                    "properties": .object(
                        InteractRunner.appResolutionSchemaProperties.merging([
                            "role": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "AX role to match (e.g., 'AXButton', 'AXTextField'). Case-insensitive substring match.",
                                ),
                            ]),
                            "title": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "Title text to match. Case-insensitive substring match.",
                                ),
                            ]),
                            "identifier": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "Accessibility identifier to match. Case-insensitive substring match.",
                                ),
                            ]),
                            "value": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "Value to match. Case-insensitive substring match.",
                                ),
                            ]),
                            "max_depth": .object([
                                "type": .string("integer"),
                                "description": .string(
                                    "Maximum depth to search. Default 10.",
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
        let maxDepth = arguments.getInt("max_depth") ?? 10
        let role = arguments.getString("role")
        let title = arguments.getString("title")
        let identifier = arguments.getString("identifier")
        let value = arguments.getString("value")

        guard role != nil || title != nil || identifier != nil || value != nil else {
            throw MCPError.invalidParams(
                "At least one search criterion (role, title, identifier, value) is required.",
            )
        }

        // Get full tree and cache it
        let fullTree = try interactRunner.getUITree(pid: pid, maxDepth: maxDepth)
        let sendableElements = fullTree.map(\.1)
        await InteractSessionManager.shared.cacheElements(pid: pid, elements: sendableElements)

        // Filter matching elements
        let matches = fullTree.filter { element, _ in
            if let role, element.role?.localizedCaseInsensitiveContains(role) != true {
                return false
            }
            if let title, element.title?.localizedCaseInsensitiveContains(title) != true {
                return false
            }
            if let identifier,
               element.identifier?.localizedCaseInsensitiveContains(identifier) != true
            {
                return false
            }
            if let value, element.value?.localizedCaseInsensitiveContains(value) != true {
                return false
            }
            return true
        }

        var lines: [String] = []
        lines.append(
            "Found \(matches.count) matching element(s) (searched \(fullTree.count) total, depth=\(maxDepth)):",
        )
        lines.append("")
        for (element, _) in matches {
            lines.append(element.summary(indent: false))
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
