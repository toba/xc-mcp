import MCP

/// Protocol for errors that can be converted to MCPError for tool responses.
///
/// Implement this protocol on domain-specific error types to provide semantic
/// mapping to appropriate MCP error types (invalidParams vs internalError).
public protocol MCPErrorConvertible: Swift.Error {
  /// Converts this error to an appropriate MCPError.
  func toMCPError() -> MCPError
}

extension Swift.Error {
  /// Converts any error to an MCPError.
  ///
  /// - If the error is already an MCPError, returns it unchanged.
  /// - If the error conforms to MCPErrorConvertible, uses `toMCPError()`.
  /// - Otherwise, wraps the error message in `MCPError.internalError`.
  public func asMCPError() -> MCPError {
    if let mcpError = self as? MCPError {
      return mcpError
    }
    if let convertible = self as? MCPErrorConvertible {
      return convertible.toMCPError()
    }
    return MCPError.internalError(localizedDescription)
  }
}
