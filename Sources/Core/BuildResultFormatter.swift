import Foundation

/// Formats a `BuildResult` into concise, structured text for MCP tool output.
public enum BuildResultFormatter {
    /// Formats a build result for display.
    ///
    /// Produces compact output like:
    /// ```
    /// Build failed (2 errors, 1 warning, 12.4s)
    ///
    /// Errors:
    ///   Sources/Foo.swift:42:10 — cannot convert 'Int' to 'String'
    ///   Sources/Bar.swift:15:5 — missing return in function
    ///
    /// Warnings:
    ///   Sources/Baz.swift:88:3 — unused variable 'x'
    /// ```
    public static func formatBuildResult(_ result: BuildResult, projectRoot: String? = nil) -> String {
        var parts: [String] = []

        // Header line
        parts.append(formatHeader(result))

        // Errors
        if !result.errors.isEmpty {
            parts.append(formatErrors(result.errors))
        }

        // Linker errors
        if !result.linkerErrors.isEmpty {
            parts.append(formatLinkerErrors(result.linkerErrors))
        }

        // Warnings (only if non-trivial count)
        if !result.warnings.isEmpty {
            if let projectRoot {
                // On success, warnings are already counted in the header — omit them
                if result.status == "success" {
                    // No warning details needed
                } else {
                    // On failure, show only project-local warnings
                    let (projectWarnings, externalCount) = partitionWarnings(
                        result.warnings, projectRoot: projectRoot,
                    )
                    if !projectWarnings.isEmpty {
                        parts.append(formatWarnings(projectWarnings))
                    }
                    if externalCount > 0 {
                        parts.append(
                            "(+\(externalCount) warning\(externalCount == 1 ? "" : "s") from dependencies hidden)",
                        )
                    }
                }
            } else {
                parts.append(formatWarnings(result.warnings))
            }
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Warning Filtering

    /// Partitions warnings into project-local and external based on file path.
    ///
    /// A warning is project-local if its file path starts with the project root.
    /// Warnings without a file path are always treated as project-local (they can't be classified).
    private static func partitionWarnings(
        _ warnings: [BuildWarning], projectRoot: String,
    ) -> (projectWarnings: [BuildWarning], externalCount: Int) {
        let root = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        var project: [BuildWarning] = []
        var externalCount = 0
        for warning in warnings {
            if let file = warning.file, !file.hasPrefix(root) {
                externalCount += 1
            } else {
                project.append(warning)
            }
        }
        return (project, externalCount)
    }

    /// Formats a test result for display.
    ///
    /// Produces compact output like:
    /// ```
    /// Tests: 42 passed, 2 failed (3.2s)
    ///
    /// Failures:
    ///   MyTests.testLogin — Expected true, got false (Sources/MyTests.swift:55)
    ///   MyTests.testLogout — Timeout after 5.0s
    /// ```
    public static func formatTestResult(_ result: BuildResult) -> String {
        var parts: [String] = []

        // Header line
        parts.append(formatTestHeader(result))

        // Failed tests
        if !result.failedTests.isEmpty {
            parts.append(formatFailedTests(result.failedTests))
        }

        // Build errors (compile errors during test build)
        if !result.errors.isEmpty {
            parts.append(formatErrors(result.errors))
        }

        // Linker errors
        if !result.linkerErrors.isEmpty {
            parts.append(formatLinkerErrors(result.linkerErrors))
        }

        // Coverage summary
        if let coverage = result.coverage {
            parts.append(
                String(format: "Coverage: %.1f%%", coverage.lineCoverage),
            )
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Header Formatting

    private static func formatHeader(_ result: BuildResult) -> String {
        var components: [String] = []

        if result.status == "success" {
            components.append("Build succeeded")
        } else {
            components.append("Build failed")
        }

        var details: [String] = []
        if result.summary.errors > 0 {
            details.append(
                "\(result.summary.errors) error\(result.summary.errors == 1 ? "" : "s")",
            )
        }
        if result.summary.linkerErrors > 0 {
            details.append(
                "\(result.summary.linkerErrors) linker error\(result.summary.linkerErrors == 1 ? "" : "s")",
            )
        }
        if result.summary.warnings > 0 {
            details.append(
                "\(result.summary.warnings) warning\(result.summary.warnings == 1 ? "" : "s")",
            )
        }
        if let buildTime = result.summary.buildTime {
            details.append(buildTime)
        }

        if !details.isEmpty {
            components.append("(\(details.joined(separator: ", ")))")
        }

        return components.joined(separator: " ")
    }

    private static func formatTestHeader(_ result: BuildResult) -> String {
        var header: String
        let passed = result.summary.passedTests ?? 0
        let failed = result.summary.failedTests

        if failed == 0, passed > 0 {
            header = "Tests passed"
        } else if failed > 0 {
            header = "Tests failed"
        } else {
            header = "Test run completed"
        }

        var details: [String] = []
        if passed > 0 {
            details.append("\(passed) passed")
        }
        if failed > 0 {
            details.append("\(failed) failed")
        }
        if let testTime = result.summary.testTime {
            details.append(testTime)
        }

        if !details.isEmpty {
            header += " (\(details.joined(separator: ", ")))"
        }

        return header
    }

    // MARK: - Detail Formatting

    private static func formatErrors(_ errors: [BuildError]) -> String {
        var lines = ["Errors:"]
        for error in errors {
            lines.append(
                "  \(formatLocation(file: error.file, line: error.line, column: error.column))\(error.message)",
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func formatLinkerErrors(_ errors: [LinkerError]) -> String {
        var lines = ["Linker errors:"]
        for error in errors {
            if !error.symbol.isEmpty {
                var detail = "  Undefined symbol '\(error.symbol)'"
                if !error.architecture.isEmpty {
                    detail += " (\(error.architecture))"
                }
                if !error.referencedFrom.isEmpty {
                    detail += " referenced from \(error.referencedFrom)"
                }
                if !error.conflictingFiles.isEmpty {
                    detail +=
                        " — duplicate in: \(error.conflictingFiles.joined(separator: ", "))"
                }
                lines.append(detail)
            } else if !error.message.isEmpty {
                lines.append("  \(error.message)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func formatWarnings(_ warnings: [BuildWarning]) -> String {
        var lines = ["Warnings:"]
        for warning in warnings {
            lines.append(
                "  \(formatLocation(file: warning.file, line: warning.line, column: warning.column))\(warning.message)",
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func formatFailedTests(_ tests: [FailedTest]) -> String {
        var lines = ["Failures:"]
        for test in tests {
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
        return lines.joined(separator: "\n")
    }

    private static func formatLocation(file: String?, line: Int?, column: Int?) -> String {
        guard let file else { return "" }
        var loc = file
        if let line {
            loc += ":\(line)"
            if let column {
                loc += ":\(column)"
            }
        }
        return loc + " — "
    }
}
