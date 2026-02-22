import MCP
import XCMCPCore
import Foundation

public struct ClearSessionDefaultsTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "clear_session_defaults",
            description:
            "Clear all session defaults, resetting project, scheme, simulator, and device settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments _: [String: Value]) async -> CallTool.Result {
        await sessionManager.clear()
        return CallTool.Result(
            content: [
                .text("Session defaults cleared."),
            ],
        )
    }
}
