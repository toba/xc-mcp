import MCP
import Foundation

/// A suggested follow-up tool call appended to a successful tool response so the model can chain
/// operations without re-deriving the next step from scratch.
///
/// Ported from getsentry/XcodeBuildMCP PR #420
/// (`feat(responses): Add next-step runtime responses`). Upstream renders both CLI and MCP
/// variants; we only emit the MCP form because we have no CLI surface.
public struct NextStepHint: Sendable {
    public let label: String
    public let tool: String
    public let params: [(key: String, value: HintValue)]
    public let priority: Int

    public init(
        label: String,
        tool: String,
        params: [(key: String, value: HintValue)] = [],
        priority: Int = 1,
    ) {
        self.label = label
        self.tool = tool
        self.params = params
        self.priority = priority
    }
}

public enum HintValue: Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)

    private static let stringEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    var rendered: String {
        switch self {
            case let .string(s):
                let data = (try? Self.stringEncoder.encode(s)) ?? Data("\"\"".utf8)
                return String(data: data, encoding: .utf8) ?? "\"\""
            case let .int(i): return String(i)
            case let .bool(b): return b ? "true" : "false"
        }
    }
}

public enum NextStepHints {
    /// Renders a `Next steps:` block sorted by priority ascending. Returns `nil` if `hints` is
    /// empty.
    public static func render(_ hints: [NextStepHint]) -> String? {
        guard !hints.isEmpty else { return nil }
        let sorted = hints.sorted { $0.priority < $1.priority }
        var lines: [String] = ["Next steps:"]

        for (i, hint) in sorted.enumerated() {
            let paramStr = hint.params.map { "\($0.key): \($0.value.rendered)" }
                .joined(separator: ", ")
            let call = paramStr.isEmpty
                ? "\(hint.tool)({})"
                : "\(hint.tool)({ \(paramStr) })"
            lines.append("\(i + 1). \(hint.label): \(call)")
        }
        return lines.joined(separator: "\n")
    }

    /// Appends a rendered hints block to an existing message body. Returns the original message
    /// unchanged if `hints` is empty.
    public static func appended(to message: String, hints: [NextStepHint]) -> String {
        guard let block = render(hints) else { return message }
        let trimmed = message.hasSuffix("\n") ? message : message + "\n"
        return trimmed + "\n" + block
    }
}
