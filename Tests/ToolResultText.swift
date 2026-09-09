import MCP
import Testing

/// The text a tool result carries in its first content item
///
/// A tool answers a call with one text item, so a test asserts on that string. This records an
/// issue and answers an empty string when the item is absent, which keeps the call site free of an
/// unwrap.
///
/// - Parameters:
///   - result: The result the tool returned.
///   - sourceLocation: The call site, so a recorded issue points at the test.
func message(
    of result: CallTool.Result,
    sourceLocation: SourceLocation = #_sourceLocation,
) -> String {
    guard case let .text(message, _, _) = result.content.first else {
        Issue.record("Expected text result", sourceLocation: sourceLocation)
        return ""
    }
    return message
}
