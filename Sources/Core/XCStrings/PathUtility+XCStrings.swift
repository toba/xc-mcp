import MCP

public extension PathUtility {
    /// Resolves `path` and runs `body` against a parser for the string catalog there
    ///
    /// Every string-catalog tool repeats the same three steps: resolve the path, build the parser,
    /// then map the failure. This owns all three. `PathError` and `XCStringsError` both conform to
    /// ``MCPErrorConvertible``, so one catch covers both, and `asMCPError` rethrows a
    /// `CancellationError` unchanged so the MCP layer still skips the response for a request the
    /// client abandoned.
    ///
    /// - Parameters:
    ///   - path: The catalog path as the caller supplied it.
    ///   - body: Receives the parser and the resolved absolute path.
    /// - Returns: Whatever `body` returns.
    func withParser<R>(
        at path: String,
        _ body: (XCStringsParser, String) async throws -> R,
    ) async throws -> R {
        do {
            let resolvedPath = try resolvePath(from: path)
            return try await body(XCStringsParser(path: resolvedPath), resolvedPath)
        } catch {
            throw try error.asMCPError()
        }
    }
}
