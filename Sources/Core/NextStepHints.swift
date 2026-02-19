import MCP

/// A suggested next tool invocation after a successful tool call.
public struct NextStepHint: Sendable {
    public let tool: String
    public let description: String

    public init(tool: String, description: String) {
        self.tool = tool
        self.description = description
    }
}

/// Generates a `.text` content block with suggested next step hints.
public enum NextStepHints {
    public static func content(hints: [NextStepHint]) -> Tool.Content {
        var lines = ["Suggested next steps:"]
        for hint in hints {
            lines.append("- \(hint.tool): \(hint.description)")
        }
        return .text(lines.joined(separator: "\n"))
    }
}
