import Foundation
import XCMCPCore
import MCP

public struct ShowSessionDefaultsTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "show_session_defaults",
            description:
                "Display the current session defaults including project, scheme, simulator, and device settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async -> CallTool.Result {
        let summary = await sessionManager.summary()
        return CallTool.Result(
            content: [
                .text("Current session defaults:\n\n\(summary)")
            ]
        )
    }
}
