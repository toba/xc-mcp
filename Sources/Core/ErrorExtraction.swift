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
    public static func extractBuildErrors(
        from output: String,
        projectRoot: String? = nil,
        errorsOnly: Bool = false,
        showWarnings: Bool = false,
    ) -> String {
        let parser = BuildOutputParser()
        let result = parser.parse(input: output)
        return BuildResultFormatter.formatBuildResult(
            result, projectRoot: projectRoot, errorsOnly: errorsOnly,
            showWarnings: showWarnings,
        )
    }

    /// Parses test output and returns a formatted summary of test results.
    ///
    /// - Parameter output: The full test output to parse.
    /// - Returns: A formatted string describing the test result.
    public static func extractTestResults(
        from output: String,
        errorsOnly: Bool = false,
    ) -> String {
        let parser = BuildOutputParser()
        let result = parser.parse(input: output)
        return BuildResultFormatter.formatTestResult(result, errorsOnly: errorsOnly)
    }

    /// Formats test output into a `CallTool.Result`, throwing on failure.
    ///
    /// - Parameters:
    ///   - output: The raw test output to parse.
    ///   - succeeded: Whether the test run succeeded.
    ///   - context: A human-readable description of the test target (e.g., "scheme 'Foo' on macOS").
    ///   - xcresultPath: Optional path to the `.xcresult` bundle for detailed results.
    ///   - stderr: Optional stderr output for detecting infrastructure issues.
    ///   - onlyTesting: The `only_testing` filters that were passed to xcodebuild, if any.
    ///   - scheme: The scheme name used for the test run, for enhanced error messages.
    /// - Returns: A successful `CallTool.Result` if tests passed.
    /// - Throws: `MCPError.internalError` if tests failed.
    public static func formatTestToolResult(
        output: String,
        succeeded inputSucceeded: Bool,
        context: String,
        xcresultPath: String? = nil,
        stderr: String? = nil,
        projectRoot: String? = nil,
        projectPath: String? = nil,
        workspacePath: String? = nil,
        onlyTesting: [String]? = nil,
        scheme: String? = nil,
        errorsOnly: Bool = false,
    ) async throws -> CallTool.Result {
        var succeeded = inputSucceeded
        var testResult: String
        var totalTestCount = 0

        // Try xcresult bundle first for complete failure messages and test output
        if let xcresultPath,
           let xcresultData = await XCResultParser.parseTestResults(at: xcresultPath)
        {
            testResult = formatXCResultData(xcresultData)
            totalTestCount =
                xcresultData.passedCount + xcresultData.failedCount
                    + xcresultData
                    .skippedCount

            // Override exit code when xcresult confirms all tests passed
            if !succeeded, xcresultData.failedCount == 0, xcresultData.passedCount > 0 {
                succeeded = true
            }

            // When xcresult shows no tests ran (0 passed, 0 failed) and the run failed,
            // the build likely failed before tests could execute. Fall back to parsing
            // stdout for compiler/linker errors that the xcresult doesn't capture.
            if !succeeded, xcresultData.passedCount == 0, xcresultData.failedCount == 0 {
                let buildErrors = extractTestResults(from: output, errorsOnly: errorsOnly)
                if !buildErrors.isEmpty {
                    testResult += "\n\n" + buildErrors
                }
            }

            // Performance measurements are in stdout, not in xcresult — parse them separately
            let parsed = parseBuildOutput(output)
            if !parsed.performanceMeasurements.isEmpty {
                testResult +=
                    "\n\n"
                    + BuildResultFormatter.formatPerformanceMeasurements(
                        parsed.performanceMeasurements,
                    )
            }
        } else {
            testResult = extractTestResults(from: output, errorsOnly: errorsOnly)

            // Extract test count and parsed status from output
            let parsed = parseBuildOutput(output)
            let passed = parsed.summary.passedTests ?? 0
            let failed = parsed.summary.failedTests
            totalTestCount = passed + failed

            // Override exit code with parsed status: swift test can exit non-zero
            // even when all tests pass (e.g. due to build warnings or toolchain quirks).
            // Only override when tests actually ran — if no tests were parsed, trust the exit code.
            if !succeeded, parsed.status == "success", totalTestCount > 0 {
                succeeded = true
            }
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

        // Enhance cryptic "not a member of the test plan" errors with actionable guidance
        if !succeeded, let projectRoot {
            if let hint = enhanceTestPlanError(
                output: output, projectRoot: projectRoot,
                projectPath: projectPath, workspacePath: workspacePath,
                scheme: scheme,
            ) {
                testResult += "\n\n" + hint
            }
        }

        // Detect zero-test runs when only_testing filters were specified
        if succeeded, let onlyTesting, !onlyTesting.isEmpty, totalTestCount == 0 {
            let filters = onlyTesting.map { "\"\($0)\"" }.joined(separator: ", ")
            throw MCPError.internalError(
                "No tests matched the only_testing filter. "
                    + "0 tests ran for \(context).\n\n"
                    + "Filters: \(filters)\n\n"
                    + "Check that identifiers use the correct format: "
                    + "\"TargetName/TestClassName/testMethodName\". "
                    + "For Swift Testing with backtick-escaped names, use: "
                    + "\"TargetName/TestClass/`method name with spaces`()\". "
                    + "Note: method-level filtering may not work for XCUI test targets — "
                    + "use class-level filtering instead (e.g. \"TargetName/TestClassName\").",
            )
        }

        let bundleSuffix = formatResultBundleSuffix(xcresultPath)

        if succeeded {
            return CallTool.Result(
                content: [.text(
                    text: "Tests passed for \(context)\n\n\(testResult)\(bundleSuffix)",
                    annotations: nil,
                    _meta: nil,
                )],
            )
        } else {
            throw MCPError.internalError("Tests failed:\n\(testResult)\(bundleSuffix)")
        }
    }

    /// Returns a `\n\nResult bundle: <path>` suffix when `path` is non-nil and the bundle
    /// exists on disk, otherwise an empty string.
    private static func formatResultBundleSuffix(_ path: String?) -> String {
        guard let path, FileManager.default.fileExists(atPath: path) else { return "" }
        return "\n\nResult bundle: \(path)"
    }

    /// Parses build output and returns the structured `BuildResult`.
    ///
    /// - Parameter output: The full build output to parse.
    /// - Returns: A structured `BuildResult` with errors, warnings, timing, etc.
    public static func parseBuildOutput(_ output: String) -> BuildResult {
        let parser = BuildOutputParser()
        return parser.parse(input: output)
    }

    /// Derives the project root directory from project or workspace paths.
    public static func projectRoot(
        projectPath: String?,
        workspacePath: String?,
    ) -> String? {
        if let projectPath {
            return URL(fileURLWithPath: projectPath).deletingLastPathComponent().path
        }
        if let workspacePath {
            return URL(fileURLWithPath: workspacePath).deletingLastPathComponent().path
        }
        return nil
    }

    /// Checks build output and throws on failure.
    ///
    /// Parses the build output, checks for success, and throws a formatted error if the build failed.
    ///
    /// - Parameters:
    ///   - result: The xcodebuild result.
    ///   - projectRoot: Optional project root for path relativization in error output.
    /// - Throws: ``MCPError/internalError(_:)`` with formatted build errors if the build failed.
    public static func checkBuildSuccess(
        _ result: ProcessResult,
        projectRoot: String?,
        errorsOnly: Bool = false,
    ) throws(MCPError) {
        let buildResult = parseBuildOutput(result.output)

        if result.succeeded || buildResult.status == "success" {
            return
        }

        let errorOutput = BuildResultFormatter.formatBuildResult(
            buildResult, projectRoot: projectRoot, errorsOnly: errorsOnly,
        )
        throw .internalError("Build failed:\n\(errorOutput)")
    }

    // MARK: - XCResult Formatting

    private static func formatXCResultData(_ data: XCResultParser.TestResults) -> String {
        var parts: [String] = []

        // Header
        let passed = data.passedCount
        let failed = data.failedCount
        let skipped = data.skippedCount
        let total = passed + failed + skipped
        var header: String
        if failed == 0, passed > 0 {
            header = "Tests passed"
        } else if failed > 0 {
            header = "Tests failed"
        } else {
            header = "Test run completed"
        }

        var details: [String] = []
        if total > 0 { details.append("\(total) total") }
        details.append("\(passed) passed")
        details.append("\(failed) failed")
        if skipped > 0 { details.append("\(skipped) skipped") }
        if let duration = data.duration {
            details.append(String(format: "%.1fs", duration))
        }
        if !details.isEmpty {
            header += " (\(details.joined(separator: ", ")))"
        }
        parts.append(header)

        // Per-test details
        if !data.tests.isEmpty {
            if total <= 50 || (failed == 0 && skipped == 0) {
                // Small suite or all passed: list every test
                var lines: [String] = []
                for test in data.tests {
                    lines.append(formatTestLine(test))
                    for metric in test.performanceMetrics {
                        lines.append(
                            "    \(metric.name): avg \(formatMetricValue(metric.average, unit: metric.unit)), "
                                + "stddev \(formatMetricValue(metric.standardDeviation, unit: metric.unit)) "
                                + "(\(metric.iterations) iterations)",
                        )
                    }
                }
                parts.append(lines.joined(separator: "\n"))
            } else {
                // Large suite with failures or skips: show only non-passing tests
                var lines: [String] = []

                let failedTests = data.tests.filter { $0.status == .failed }
                if !failedTests.isEmpty {
                    lines.append("Failed:")
                    for test in failedTests {
                        lines.append(formatTestLine(test))
                    }
                }

                let skippedTests = data.tests.filter { $0.status == .skipped }
                if !skippedTests.isEmpty {
                    if !lines.isEmpty { lines.append("") }
                    lines.append("Skipped:")
                    for test in skippedTests {
                        lines.append(formatTestLine(test))
                    }
                }

                if !lines.isEmpty {
                    parts.append(lines.joined(separator: "\n"))
                }
            }

            // Opt-in timing block: surface slow passing tests that are otherwise
            // hidden when total > 50 and there are failures.
            if showTestTimingEnabled() {
                if let block = formatTestTimings(data.tests) {
                    parts.append(block)
                }
            }
        } else if !data.failures.isEmpty {
            // Fall back to failure-only listing when per-test details unavailable
            var lines = ["Failed:"]
            for test in data.failures {
                var detail = "  ✗ \(test.test) — \(test.message)"
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

    private static func formatTestLine(_ test: XCResultParser.TestDetail) -> String {
        switch test.status {
            case .passed:
                let dur = test.duration.map { String(format: " (%.1fs)", $0) } ?? ""
                return "  ✓ \(test.name)\(dur)"
            case .failed:
                let dur = test.duration.map { String(format: " (%.1fs)", $0) } ?? ""
                let msg = test.failureMessage.map { " — \($0)" } ?? ""
                return "  ✗ \(test.name)\(dur)\(msg)"
            case .skipped:
                let reason = test.skipReason.map { " — skipped: \($0)" } ?? " — skipped"
                return "  ⊘ \(test.name)\(reason)"
            case .expectedFailure:
                let dur = test.duration.map { String(format: " (%.1fs)", $0) } ?? ""
                return "  ✓ \(test.name)\(dur) (expected failure)"
        }
    }

    /// Whether to render the optional per-test timing block in xcresult-formatted output.
    ///
    /// Toggled via `XC_MCP_SHOW_TEST_TIMING` (any non-empty, non-`0`/`false` value enables it).
    private static func showTestTimingEnabled() -> Bool {
        guard let value = ProcessInfo.processInfo.environment["XC_MCP_SHOW_TEST_TIMING"],
              !value.isEmpty
        else { return false }
        let lowered = value.lowercased()
        return lowered != "0" && lowered != "false" && lowered != "no"
    }

    /// Renders the top-N tests by duration, sorted descending. Returns `nil` if no tests
    /// have a recorded duration.
    private static func formatTestTimings(
        _ tests: [XCResultParser.TestDetail],
        limit: Int = 10,
    ) -> String? {
        let sorted = tests
            .compactMap { test -> (XCResultParser.TestDetail, Double)? in
                guard let duration = test.duration else { return nil }
                return (test, duration)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)

        guard !sorted.isEmpty else { return nil }

        var lines = ["Test timings (slowest \(sorted.count)):"]
        for (test, duration) in sorted {
            let icon =
                switch test.status {
                    case .passed, .expectedFailure: "✓"
                    case .failed: "✗"
                    case .skipped: "⊘"
                }
            lines.append(String(format: "  %@ %@ (%.3fs)", icon, test.name, duration))
        }
        return lines.joined(separator: "\n")
    }

    private static func formatMetricValue(_ value: Double, unit: String) -> String {
        switch unit {
            case "ms": return String(format: "%.2fms", value)
            case "s": return String(format: "%.1fs", value)
            case "kB", "KB": return String(format: "%.1fkB", value)
            case "MB": return String(format: "%.1fMB", value)
            default: return String(format: "%.2f%@", value, unit)
        }
    }

    // MARK: - only_testing Pre-Validation

    /// Result of validating `only_testing` entries against available test targets.
    public struct OnlyTestingValidation {
        /// Entries whose target component matches a known test target.
        public let valid: [String]
        /// Human-readable warning about removed entries, or nil if all were valid.
        public let warning: String?
    }

    /// Validates `only_testing` entries against the scheme's available test targets.
    ///
    /// Extracts the target component (before the first `/`) from each entry and checks
    /// it against test plan targets and scheme testable references.
    ///
    /// - Returns: The valid entries and an optional warning about removed invalid entries.
    public static func validateOnlyTesting(
        _ entries: [String],
        projectRoot: String,
        projectPath: String?,
        workspacePath: String?,
        scheme: String?,
    ) -> OnlyTestingValidation {
        let availableTargets = discoverTestTargets(
            projectRoot: projectRoot,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
        )

        // If we can't discover any targets, skip validation to avoid false positives
        guard !availableTargets.isEmpty else {
            return OnlyTestingValidation(valid: entries, warning: nil)
        }

        var valid: [String] = []
        var invalid: [String] = []
        for entry in entries {
            let targetName = extractTargetName(from: entry)
            if availableTargets.contains(targetName) {
                valid.append(entry)
            } else {
                invalid.append(entry)
            }
        }

        guard !invalid.isEmpty else {
            return OnlyTestingValidation(valid: entries, warning: nil)
        }

        let invalidList = invalid.map { "\"\($0)\"" }.joined(separator: ", ")
        let availableList = availableTargets.sorted().joined(separator: ", ")
        let warning =
            "Warning: Removed invalid only_testing entries: \(invalidList). "
                + "Available test targets: \(availableList)."

        return OnlyTestingValidation(valid: valid, warning: warning)
    }

    /// Extracts the target name (first path component) from a test identifier.
    private static func extractTargetName(from identifier: String) -> String {
        if let slashIndex = identifier.firstIndex(of: "/") {
            return String(identifier[..<slashIndex])
        }
        return identifier
    }

    /// Discovers available test targets from test plans and scheme files.
    private static func discoverTestTargets(
        projectRoot: String,
        projectPath: String?,
        workspacePath: String?,
        scheme: String?,
    ) -> Set<String> {
        var targets: Set<String> = []

        // Discover from .xctestplan files
        let testPlanFiles = TestPlanFile.findFiles(under: projectRoot)
        for planFile in testPlanFiles {
            let entries = TestPlanFile.targetEntries(from: planFile.json)
            for entry in entries where entry.enabled {
                targets.insert(entry.name)
            }
        }

        // Also discover from scheme files
        let projectPaths = discoverProjectPaths(
            projectPath: projectPath, workspacePath: workspacePath,
        )
        let schemeMap = buildSchemeTestTargetMap(projectPaths: projectPaths)

        if targets.isEmpty {
            if let scheme, let schemeTargets = schemeMap[scheme] {
                targets = schemeTargets
            } else {
                for schemeTargets in schemeMap.values {
                    targets.formUnion(schemeTargets)
                }
            }
        }

        return targets
    }

    // MARK: - Test Plan Error Enhancement

    /// Detects "not a member of the specified test plan or scheme" errors and enhances
    /// them with available test targets, the correct identifier format, and scheme suggestions.
    private static func enhanceTestPlanError(
        output: String,
        projectRoot: String,
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String? = nil,
    ) -> String? {
        // xcodebuild emits: "... isn't a member of the specified test plan or scheme."
        guard
            output.contains("isn't a member of the specified test plan or scheme")
            || output.contains("is not a member of the specified test plan or scheme")
        else {
            return nil
        }

        // Extract the identifier names from the error message
        // Pattern: "\"SomeName\" isn't a member of..."
        let identifierPattern = /\"([^\"]+)\"\s+isn't a member of the specified test plan or scheme/
        var badIdentifiers: [String] = []
        for match in output.matches(of: identifierPattern) {
            badIdentifiers.append(String(match.1))
        }

        // Discover available test targets from .xctestplan files
        let testPlanFiles = TestPlanFile.findFiles(under: projectRoot)
        var allTargets: [String] = []
        for planFile in testPlanFiles {
            let entries = TestPlanFile.targetEntries(from: planFile.json)
            for entry in entries where entry.enabled {
                if !allTargets.contains(entry.name) {
                    allTargets.append(entry.name)
                } // sm:ignore useOrderedSetForUniqueAppend
            }
        }

        // Also discover test targets from scheme files (covers projects without .xctestplan files)
        let projectPaths = discoverProjectPaths(
            projectPath: projectPath, workspacePath: workspacePath,
        )
        let schemeMap = buildSchemeTestTargetMap(projectPaths: projectPaths)

        // If no test plan targets found, use scheme targets instead
        if allTargets.isEmpty {
            // Prefer targets from the current scheme
            if let scheme, let currentSchemeTargets = schemeMap[scheme],
               !currentSchemeTargets.isEmpty
            {
                allTargets = currentSchemeTargets.sorted()
            } else {
                // Fall back to all targets across all schemes
                var seen: Set<String> = []
                for targets in schemeMap.values {
                    for target in targets where seen.insert(target).inserted {
                        allTargets.append(target)
                    }
                }
                allTargets.sort()
            }
        }

        var hint = ""
        if badIdentifiers.isEmpty {
            hint +=
                "The only_testing identifier is not a member of the specified test plan or scheme."
        } else {
            let quoted = badIdentifiers.map { "\"\($0)\"" }.joined(separator: ", ")
            hint += "\(quoted) is not a valid test identifier."
        }

        if !allTargets.isEmpty {
            if let scheme {
                hint += " Available test targets for scheme '\(scheme)': "
            } else {
                hint += " Available test targets: "
            }
            hint += allTargets.joined(separator: ", ") + "."
        }

        hint +=
            " Use format \"TargetName/TestClassName\" or \"TargetName/TestClassName/testMethodName\"."

        if !allTargets.isEmpty, let firstTarget = allTargets.first, !badIdentifiers.isEmpty {
            // Extract the class/method part from the bad identifier to build a better example
            let classOrMethod: String
            if let slashIndex = badIdentifiers[0].firstIndex(of: "/") {
                classOrMethod =
                    String(badIdentifiers[0][badIdentifiers[0].index(after: slashIndex)...])
            } else {
                classOrMethod = badIdentifiers[0]
            }
            let example = "\(firstTarget)/\(classOrMethod)"
            hint += " For example: \"\(example)\"."
        }

        // Suggest schemes that contain the missing test target
        let schemeSuggestion = suggestSchemesForTargets(
            badIdentifiers, projectPath: projectPath, workspacePath: workspacePath,
        )
        if let schemeSuggestion {
            hint += " " + schemeSuggestion
        }

        return hint
    }

    /// Scans `.xcscheme` files to find which schemes include the given test targets,
    /// then returns a suggestion string.
    private static func suggestSchemesForTargets(
        _ identifiers: [String], projectPath: String?, workspacePath: String?,
    ) -> String? {
        // Collect all .xcodeproj paths to scan for schemes
        let projectPaths = discoverProjectPaths(
            projectPath: projectPath, workspacePath: workspacePath,
        )
        guard !projectPaths.isEmpty else { return nil }

        // Build a map of scheme name → set of test target names
        let schemeMap = buildSchemeTestTargetMap(projectPaths: projectPaths)
        guard !schemeMap.isEmpty else { return nil }

        // Extract target names from identifiers (the part before the first slash)
        let targetNames = identifiers.map { id -> String in
            if let slashIndex = id.firstIndex(of: "/") {
                return String(id[id.startIndex ..< slashIndex])
            }
            return id
        }

        // Find schemes that contain each target
        var suggestions: [String] = []
        for targetName in targetNames {
            let matchingSchemes =
                schemeMap
                    .filter { $0.value.contains(targetName) }
                    .map(\.key)
                    .sorted()
            if !matchingSchemes.isEmpty {
                let schemeList = matchingSchemes.map { "'\($0)'" }.joined(separator: ", ")
                suggestions.append(
                    "Target '\(targetName)' is in scheme \(schemeList).",
                )
            }
        }

        if suggestions.isEmpty { return nil }
        return "Did you mean a different scheme? " + suggestions.joined(separator: " ")
    }

    /// Returns all `.xcodeproj` paths relevant to the current build context.
    private static func discoverProjectPaths(
        projectPath: String?, workspacePath: String?,
    ) -> [String] {
        if let projectPath {
            return [projectPath]
        }
        guard let workspacePath else { return [] }

        // For workspaces, read contents.xcworkspacedata to find referenced .xcodeproj files
        let contentsPath = "\(workspacePath)/contents.xcworkspacedata"
        guard let data = FileManager.default.contents(atPath: contentsPath),
              let xml = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let fm = FileManager.default
        let workspaceDir = URL(fileURLWithPath: workspacePath).deletingLastPathComponent().path
        var paths: [String] = []

        // Pattern: location = "group:relative/path.xcodeproj"
        let locationPattern = /location\s*=\s*"group:([^"]+\.xcodeproj)"/
        for match in xml.matches(of: locationPattern) {
            let relativePath = String(match.1)
            let fullPath = "\(workspaceDir)/\(relativePath)"
            let resolved = URL(fileURLWithPath: fullPath).standardized.path
            if fm.fileExists(atPath: resolved) {
                paths.append(resolved)
            }
        }

        return paths
    }

    /// Builds a mapping from scheme name to the set of test target names in that scheme.
    private static func buildSchemeTestTargetMap(
        projectPaths: [String],
    ) -> [String: Set<String>] {
        let fm = FileManager.default
        var result: [String: Set<String>] = [:]

        for projectPath in projectPaths {
            for schemeDir in SchemePathResolver.schemeDirs(for: projectPath) {
                guard let files = try? fm.contentsOfDirectory(atPath: schemeDir) else { continue }
                for file in files where file.hasSuffix(".xcscheme") {
                    let schemeName = String(file.dropLast(".xcscheme".count))
                    let schemePath = "\(schemeDir)/\(file)"
                    let targets = extractTestTargets(fromSchemeAt: schemePath)
                    if !targets.isEmpty {
                        result[schemeName, default: []].formUnion(targets)
                    }
                }
            }
        }

        return result
    }

    /// Extracts test target names from a `.xcscheme` XML file by parsing
    /// `BlueprintName` attributes within `TestableReference` elements.
    private static func extractTestTargets(fromSchemeAt path: String) -> Set<String> {
        guard let data = FileManager.default.contents(atPath: path),
              let xml = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var targets: Set<String> = []

        // Match TestableReference blocks and extract BlueprintName.
        // We look for TestableReference that is not skipped, then find BlueprintName inside.
        let testablePattern =
            /TestableReference\s[^>]*?skipped\s*=\s*"NO"[\s\S]*?BlueprintName\s*=\s*"([^"]+)"/
        for match in xml.matches(of: testablePattern) {
            targets.insert(String(match.1))
        }

        // Also match when skipped attribute comes after other attributes or is absent
        // (default is not skipped)
        let altPattern =
            /TestableReference[^>]*>\s*<BuildableReference[^>]*BlueprintName\s*=\s*"([^"]+)"/
        for match in xml.matches(of: altPattern) {
            targets.insert(String(match.1))
        }

        return targets
    }

    // MARK: - Compiler Crash Detection

    /// Signal crash patterns in compiler output.
    ///
    /// When `swift build` encounters a compiler crash (SIGABRT, SIGSEGV, etc.),
    /// the output contains messages like:
    /// ```
    /// <unknown>:0: error: compile command failed due to signal 6 (use -v to see invocation)
    /// ```
    private static nonisolated(unsafe) let compilerCrashPattern =
        /compile command failed due to signal (\d+)/

    /// Returns the signal number if the build output contains a compiler signal crash,
    /// or `nil` if no crash was detected.
    public static func detectCompilerCrash(in output: String) -> Int? {
        guard let match = output.firstMatch(of: compilerCrashPattern) else {
            return nil
        }
        return Int(match.1)
    }

    /// Extracts the crashing compilation unit and compiler backtrace from verbose
    /// build output after a signal crash retry.
    ///
    /// With `-v`, the compiler emits the full `swiftc` invocation that crashed,
    /// making it possible to identify which file triggered the crash.
    public static func extractCrashDetails(from verboseOutput: String, signal: Int) -> String {
        var sections: [String] = []
        sections.append("Compiler crashed (signal \(signal))")

        // Extract the crashing file from the swiftc invocation preceding the crash.
        // The verbose output shows the full command, then the crash message.
        let lines = verboseOutput.split(separator: "\n", omittingEmptySubsequences: false)
        var crashingInvocation: String?
        var crashingFiles: [String] = []

        for (index, line) in lines.enumerated() {
            if line.contains("compile command failed due to signal") {
                // Walk backwards to find the swiftc invocation
                var i = index - 1
                while i >= 0 {
                    let prev = String(lines[i])
                    if prev.contains("swiftc") || prev.contains("swift-frontend") {
                        crashingInvocation = prev
                        break
                    }
                    i -= 1
                }
                // Extract .swift files from the invocation
                if let invocation = crashingInvocation {
                    let tokens = invocation.split(separator: " ")
                    for token in tokens {
                        let t = String(token)
                        if t.hasSuffix(".swift"), !t.hasPrefix("-") {
                            crashingFiles.append(t)
                        }
                    }
                }
                break
            }
        }

        if !crashingFiles.isEmpty {
            if crashingFiles.count == 1 {
                sections.append("Crashing file: \(crashingFiles[0])")
            } else {
                sections.append(
                    "Crashing compilation unit (\(crashingFiles.count) files):\n"
                        + crashingFiles.map { "  \($0)" }.joined(separator: "\n"),
                )
            }
        }

        // Include the swiftc invocation for context
        if let invocation = crashingInvocation {
            // Truncate very long invocations (they can span thousands of characters)
            let maxLen = 2000
            let truncated =
                invocation.count > maxLen
                    ? String(invocation.prefix(maxLen)) + "…"
                    : invocation
            sections.append("Compiler invocation:\n\(truncated)")
        }

        // Extract stack trace if present (compiler sometimes dumps this)
        let stackLines = lines.filter {
            $0.contains("Stack dump:") || $0.hasPrefix("0 ") || $0.hasPrefix("1 ")
                || $0.contains("#0") || $0.contains("swift::") || $0.contains("llvm::")
        }
        if !stackLines.isEmpty {
            let trace = stackLines.prefix(20).map(String.init).joined(separator: "\n")
            sections.append("Compiler backtrace:\n\(trace)")
        }

        return sections.joined(separator: "\n\n")
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
