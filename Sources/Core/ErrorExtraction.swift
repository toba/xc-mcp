import MCP
import Foundation

/// Utilities for extracting error information from build and test output.
public enum ErrorExtractor {
    /// Parses build output and returns a formatted summary of errors, warnings, and timing.
    ///
    /// Uses `BuildOutputParser` for structured parsing and `BuildResultFormatter` for display.
    ///
    /// - Parameter output: The full build output to parse.
    /// - Returns: A formatted string describing the build result.
    public static func extractBuildErrors(from output: String,
                                          projectRoot: String? = nil) -> String
    {
        let parser = BuildOutputParser()
        let result = parser.parse(input: output)
        return BuildResultFormatter.formatBuildResult(result, projectRoot: projectRoot)
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
    ///   - xcresultPath: Optional path to the `.xcresult` bundle for detailed results.
    ///   - stderr: Optional stderr output for detecting infrastructure issues.
    /// - Returns: A successful `CallTool.Result` if tests passed.
    /// - Throws: `MCPError.internalError` if tests failed.
    public static func formatTestToolResult(
        output: String,
        succeeded: Bool,
        context: String,
        xcresultPath: String? = nil,
        stderr: String? = nil,
    ) throws -> CallTool.Result {
        var testResult: String

        // Try xcresult bundle first for complete failure messages and test output
        if let xcresultPath,
           let xcresultData = XCResultParser.parseTestResults(at: xcresultPath)
        {
            testResult = formatXCResultData(xcresultData)

            // When xcresult shows no tests ran (0 passed, 0 failed) and the run failed,
            // the build likely failed before tests could execute. Fall back to parsing
            // stdout for compiler/linker errors that the xcresult doesn't capture.
            if !succeeded, xcresultData.passedCount == 0, xcresultData.failedCount == 0 {
                let buildErrors = extractTestResults(from: output)
                if !buildErrors.isEmpty {
                    testResult += "\n\n" + buildErrors
                }
            }
        } else {
            testResult = extractTestResults(from: output)
        }

        // Check for testmanagerd crashes in stderr
        if let stderr {
            let warnings = detectInfrastructureWarnings(stderr: stderr)
            if !warnings.isEmpty {
                testResult += "\n\n" + warnings
            }
        }

        // Detect UI test misconfiguration (missing target application)
        if !succeeded,
           output.contains("NSInternalInconsistencyException"),
           output.contains("XCTestConfiguration")
           || output.contains("targetApplicationBundleID")
        {
            testResult +=
                "\n\nUI test target has no target application configured. "
                + "Use set_test_target_application to configure the host app in the scheme's Test action."
        }

        if succeeded {
            return CallTool.Result(
                content: [.text("Tests passed for \(context)\n\n\(testResult)")],
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

    // MARK: - XCResult Formatting

    private static func formatXCResultData(_ data: XCResultParser.TestResults) -> String {
        var parts: [String] = []

        // Header
        let passed = data.passedCount
        let failed = data.failedCount
        var header: String
        if failed == 0, passed > 0 {
            header = "Tests passed"
        } else if failed > 0 {
            header = "Tests failed"
        } else {
            header = "Test run completed"
        }

        var details: [String] = []
        if passed > 0 { details.append("\(passed) passed") }
        if failed > 0 { details.append("\(failed) failed") }
        if let duration = data.duration {
            details.append(String(format: "%.1fs", duration))
        }
        if !details.isEmpty {
            header += " (\(details.joined(separator: ", ")))"
        }
        parts.append(header)

        // Failures
        if !data.failures.isEmpty {
            var lines = ["Failures:"]
            for test in data.failures {
                var detail = "  \(test.test) — \(test.message)"
                if let file = test.file {
                    detail += " (\(file)"
                    if let line = test.line {
                        detail += ":\(line)"
                    }
                    detail += ")"
                }
                lines.append(detail)
            }
            parts.append(lines.joined(separator: "\n"))
        }

        // Test output (stdout from XCUI tests)
        if let testOutput = data.testOutput, !testOutput.isEmpty {
            parts.append("Test output:\n\(testOutput)")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Infrastructure Warning Detection

    /// Detects testmanagerd crashes and other test infrastructure issues from stderr.
    private static func detectInfrastructureWarnings(stderr: String) -> String {
        var warnings: [String] = []

        // testmanagerd crash (SIGSEGV, SIGABRT, etc.)
        if stderr.contains("testmanagerd"),
           stderr.contains("crash") || stderr.contains("SIGSEGV")
           || stderr.contains("SIGABRT") || stderr.contains("SIGBUS")
           || stderr.contains("pointer authentication")
           || stderr.contains("pointer auth")
           || stderr.contains("EXC_BAD_ACCESS")
        {
            warnings.append(
                "Warning: testmanagerd crashed during the test run. "
                    + "Test results may be incomplete or unreliable. "
                    + "Consider re-running the tests.",
            )
        }

        // testmanagerd mentioned with "terminated" or "exited"
        if stderr.contains("testmanagerd"),
           stderr.contains("terminated unexpectedly")
           || stderr.contains("exited unexpectedly")
           || stderr.contains("lost connection")
        {
            if warnings.isEmpty {
                warnings.append(
                    "Warning: testmanagerd terminated unexpectedly during the test run. "
                        + "Test results may be incomplete.",
                )
            }
        }

        // XCTest runner daemon issues
        if stderr.contains("IDETestRunnerDaemon"), stderr.contains("crash") {
            warnings.append(
                "Warning: The test runner daemon crashed during the test run.",
            )
        }

        return warnings.joined(separator: "\n")
    }
}
