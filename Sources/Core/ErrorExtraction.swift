import Foundation
import MCP

/// Utilities for extracting error information from build and test output.
public enum ErrorExtractor {

    /// Parses build output and returns a formatted summary of errors, warnings, and timing.
    ///
    /// Uses `BuildOutputParser` for structured parsing and `BuildResultFormatter` for display.
    ///
    /// - Parameter output: The full build output to parse.
    /// - Returns: A formatted string describing the build result.
    public static func extractBuildErrors(from output: String) -> String {
        let parser = BuildOutputParser()
        let result = parser.parse(input: output)
        return BuildResultFormatter.formatBuildResult(result)
    }

    /// Parses test output and returns a formatted summary of test results.
    ///
    /// - Parameter output: The full test output to parse.
    /// - Returns: A formatted string describing the test result.
    public static func extractTestResults(from output: String) -> String {
        let parser = BuildOutputParser()
        let result = parser.parse(input: output)
        return BuildResultFormatter.formatTestResult(result)
    }

    /// Formats test output into a `CallTool.Result`, throwing on failure.
    ///
    /// - Parameters:
    ///   - output: The raw test output to parse.
    ///   - succeeded: Whether the test run succeeded.
    ///   - context: A human-readable description of the test target (e.g., "scheme 'Foo' on macOS").
    /// - Returns: A successful `CallTool.Result` if tests passed.
    /// - Throws: `MCPError.internalError` if tests failed.
    public static func formatTestToolResult(
        output: String, succeeded: Bool, context: String
    ) throws -> CallTool.Result {
        let testResult = extractTestResults(from: output)
        if succeeded {
            return CallTool.Result(
                content: [.text("Tests passed for \(context)\n\n\(testResult)")]
            )
        } else {
            throw MCPError.internalError("Tests failed:\n\(testResult)")
        }
    }

    /// Parses build output and returns the structured `BuildResult`.
    ///
    /// - Parameter output: The full build output to parse.
    /// - Returns: A structured `BuildResult` with errors, warnings, timing, etc.
    public static func parseBuildOutput(_ output: String) -> BuildResult {
        let parser = BuildOutputParser()
        return parser.parse(input: output)
    }
}
