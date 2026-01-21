import Foundation

/// Utilities for extracting error information from build output.
public enum ErrorExtractor {
    /// Extracts build errors from xcodebuild or swift build output.
    ///
    /// Filters the output for lines containing error indicators like "error:"
    /// or "BUILD FAILED". If no specific errors are found, returns the last
    /// few lines of output for context.
    ///
    /// - Parameters:
    ///   - output: The full build output to search.
    ///   - contextLines: Number of trailing lines to return if no errors found. Defaults to 20.
    /// - Returns: A string containing either the filtered error lines or trailing context.
    public static func extractBuildErrors(from output: String, contextLines: Int = 20) -> String {
        let lines = output.components(separatedBy: .newlines)
        let errorLines = lines.filter {
            $0.contains("error:") || $0.contains("BUILD FAILED")
        }

        if errorLines.isEmpty {
            return lines.suffix(contextLines).joined(separator: "\n")
        }

        return errorLines.joined(separator: "\n")
    }
}
