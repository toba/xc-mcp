import Foundation
import MCP
import XCMCPCore

public struct InteractMenuTool: Sendable {
    private let interactRunner: InteractRunner

    public init(interactRunner: InteractRunner) {
        self.interactRunner = interactRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "interact_menu",
            description:
                "Navigate and click a menu bar item in a macOS application by path. "
                + "Provide a menu path array like [\"File\", \"Export\", \"PDF\"] to open submenus and click the final item.",
            inputSchema: .object(
                [
                    "type": .string("object"),
                    "properties": .object(
                        InteractRunner.appResolutionSchemaProperties.merging([
                            "menu_path": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string")]),
                                "description": .string(
                                    "Array of menu item titles to navigate, e.g. [\"File\", \"Save As...\"]."
                                ),
                            ])
                        ]) { _, new in new }),
                    "required": .array([.string("menu_path")]),
                ]
            )
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let pid = try interactRunner.resolveAppFromArguments(arguments)
        let menuPath = arguments.getStringArray("menu_path")
        guard !menuPath.isEmpty else {
            throw MCPError.invalidParams("menu_path must be a non-empty array of menu item titles.")
        }

        try interactRunner.navigateMenu(pid: pid, menuPath: menuPath)

        return CallTool.Result(
            content: [.text("Clicked menu: \(menuPath.joined(separator: " > "))")])
    }
}
