import MCP

public extension CallTool.Result {
    /// A result carrying `message` as its only text content
    ///
    /// `Tool.Content.text` declares no default for `annotations` or `_meta`, and the SDK factory
    /// that omits them is deprecated. This keeps the full spelling in one place.
    static func text(_ message: String) -> Self {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }
}
