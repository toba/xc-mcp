// Adapted from xcsift (MIT License) - https://github.com/ldomaradzki/xcsift
import Foundation

/// Parses xcodebuild and swift build output into structured build results.
///
/// Extracts errors, warnings, linker errors, test failures, build timing,
/// and code coverage from raw build output text.
public final class BuildOutputParser: @unchecked Sendable {
    private var errors: [BuildError] = []
    private var warnings: [BuildWarning] = []
    private var failedTests: [FailedTest] = []
    private var linkerErrors: [LinkerError] = []
    private var executables: [Executable] = []
    private var seenExecutablePaths: Set<String> = []
    private var buildTime: String?
    private var testTimeAccumulator: Double = 0
    private var seenTestNames: Set<String> = []
    private var seenWarnings: Set<String> = []
    private var seenErrors: Set<String> = []
    private var seenLinkerErrors: Set<String> = []
    private var xctestExecutedCount: Int?
    private var xctestFailedCount: Int?
    private var swiftTestingExecutedCount: Int?
    private var swiftTestingFailedCount: Int?
    private var passedTestsCount: Int = 0
    private var seenPassedTestNames: Set<String> = []
    private var parallelTestsTotalCount: Int?
    private var testRunFailed: Bool = false

    // Linker error parsing state
    private var currentLinkerArchitecture: String?
    private var pendingLinkerSymbol: String?

    // Duplicate symbol parsing state
    private var pendingDuplicateSymbol: String?
    private var pendingConflictingFiles: [String] = []

    // Test duration tracking for slow/flaky detection
    private var passedTestDurations: [String: Double] = [:]
    private var failedTestDurations: [String: Double] = [:]

    // Build info tracking
    private var targetPhases: [String: [String]] = [:]
    private var targetDurations: [String: String] = [:]
    private var targetOrder: [String] = []
    private var shouldParseBuildInfo: Bool = false

    // Dependency graph tracking
    private var targetDependencies: [String: [String]] = [:]
    private var currentDependencyTarget: String?

    public init() {}

    /// Parses build/test output into a structured `BuildResult`.
    public func parse(
        input: String,
        coverage: CodeCoverage? = nil,
        slowThreshold: Double? = nil,
        parseBuildInfo: Bool = false
    ) -> BuildResult {
        resetState()
        shouldParseBuildInfo = parseBuildInfo
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (index, line) in lines.enumerated() {
            parseLine(line)

            if line.contains("Command PhaseScriptExecution failed with a nonzero exit") {
                var contextLines: [String] = []
                let startIndex = max(0, index - 3)
                for contextIdx in startIndex..<index {
                    let contextLine = lines[contextIdx].trimmingCharacters(in: .whitespaces)
                    if contextLine.isEmpty || contextLine.hasPrefix("Warning:")
                        || contextLine.hasPrefix("Run script build phase")
                    {
                        continue
                    }
                    if contextLine.contains(": warning:") && !contextLine.contains("error:") {
                        continue
                    }
                    contextLines.append(contextLine)
                }

                if !contextLines.isEmpty, let lastIndex = errors.indices.last,
                    errors[lastIndex].message == line
                {
                    let combinedMessage = contextLines.joined(separator: " ") + " " + line
                    errors[lastIndex] = BuildError(
                        file: nil, line: nil, message: combinedMessage
                    )
                }
            }
        }

        // Aggregate test counts from both XCTest and Swift Testing
        let totalExecuted: Int? = {
            if let parallelTotal = parallelTestsTotalCount {
                if let xctest = xctestExecutedCount {
                    return parallelTotal + xctest
                }
                return parallelTotal
            }
            let xctest = xctestExecutedCount ?? 0
            let swiftTesting = swiftTestingExecutedCount ?? 0
            if xctest > 0 || swiftTesting > 0 {
                return xctest + swiftTesting
            }
            return nil
        }()

        let totalFailed: Int = {
            let xctestFailed = xctestFailedCount ?? 0
            let swiftTestingFailed = swiftTestingFailedCount ?? 0
            let aggregated = xctestFailed + swiftTestingFailed
            return aggregated > 0 ? aggregated : failedTests.count
        }()

        let computedPassedTests: Int? = {
            if let executed = totalExecuted {
                return max(executed - totalFailed, 0)
            }
            if passedTestsCount > 0 {
                return passedTestsCount
            }
            return nil
        }()

        let status: String = {
            let hasActualFailures =
                !errors.isEmpty || !failedTests.isEmpty || !linkerErrors.isEmpty
            let hasPassedTests = (computedPassedTests ?? 0) > 0

            switch (hasActualFailures, testRunFailed, hasPassedTests) {
            case (true, _, _):
                return "failed"
            case (false, true, true):
                return "success"
            case (false, true, false):
                return "failed"
            case (false, false, _):
                return "success"
            }
        }()

        let slowTests: [SlowTest] = {
            guard let threshold = slowThreshold else { return [] }
            return detectSlowTests(threshold: threshold)
        }()

        let flakyTests = detectFlakyTests()

        let formattedTestTime: String? =
            testTimeAccumulator > 0
            ? String(format: "%.3fs", testTimeAccumulator)
            : nil

        let summary = BuildSummary(
            errors: errors.count,
            warnings: warnings.count,
            failedTests: totalFailed,
            linkerErrors: linkerErrors.count,
            passedTests: computedPassedTests,
            buildTime: buildTime,
            testTime: formattedTestTime,
            coveragePercent: coverage?.lineCoverage,
            slowTests: slowTests.isEmpty ? nil : slowTests.count,
            flakyTests: flakyTests.isEmpty ? nil : flakyTests.count,
            executables: executables.isEmpty ? nil : executables.count
        )

        let buildInfo: BuildInfo? =
            parseBuildInfo
            ? {
                let targets = targetOrder.map { targetName in
                    TargetBuildInfo(
                        name: targetName,
                        duration: targetDurations[targetName],
                        phases: targetPhases[targetName] ?? [],
                        dependsOn: targetDependencies[targetName] ?? []
                    )
                }
                let slowestTargets = computeSlowestTargets(targets: targets, limit: 5)
                return BuildInfo(targets: targets, slowestTargets: slowestTargets)
            }() : nil

        return BuildResult(
            status: status,
            summary: summary,
            errors: errors,
            warnings: warnings,
            failedTests: failedTests,
            linkerErrors: linkerErrors,
            coverage: coverage,
            slowTests: slowTests,
            flakyTests: flakyTests,
            buildInfo: buildInfo,
            executables: executables
        )
    }

    // MARK: - Slow/Flaky Test Detection

    private func detectSlowTests(threshold: Double) -> [SlowTest] {
        var slow: [SlowTest] = []
        var seenNames: Set<String> = []

        for (name, duration) in passedTestDurations where duration > threshold {
            slow.append(SlowTest(test: name, duration: duration))
            seenNames.insert(name)
        }

        for (name, duration) in failedTestDurations where duration > threshold {
            if !seenNames.contains(name) {
                slow.append(SlowTest(test: name, duration: duration))
            }
        }

        return slow.sorted { $0.duration > $1.duration }
    }

    private func detectFlakyTests() -> [String] {
        let passedNames = Set(passedTestDurations.keys)
        let failedNames = Set(failedTests.map { normalizeTestName($0.test) })
        return Array(passedNames.intersection(failedNames)).sorted()
    }

    private func computeSlowestTargets(targets: [TargetBuildInfo], limit: Int) -> [String] {
        func parseDuration(_ duration: String?) -> Double {
            guard let d = duration, d.hasSuffix("s") else { return 0 }
            return Double(d.dropLast()) ?? 0
        }

        let sorted =
            targets
            .filter { $0.duration != nil }
            .sorted { parseDuration($0.duration) > parseDuration($1.duration) }

        return Array(sorted.prefix(limit).map(\.name))
    }

    private func resetState() {
        errors = []
        warnings = []
        failedTests = []
        linkerErrors = []
        executables = []
        seenExecutablePaths = []
        buildTime = nil
        testTimeAccumulator = 0
        seenTestNames = []
        xctestExecutedCount = nil
        xctestFailedCount = nil
        swiftTestingExecutedCount = nil
        swiftTestingFailedCount = nil
        passedTestsCount = 0
        seenPassedTestNames = []
        currentLinkerArchitecture = nil
        pendingLinkerSymbol = nil
        pendingDuplicateSymbol = nil
        pendingConflictingFiles = []
        parallelTestsTotalCount = nil
        testRunFailed = false
        passedTestDurations = [:]
        failedTestDurations = [:]
        targetPhases = [:]
        targetDurations = [:]
        targetOrder = []
        shouldParseBuildInfo = false
        targetDependencies = [:]
        currentDependencyTarget = nil
    }

    private func parseLine(_ line: String) {
        if line.isEmpty || line.count > 5000 {
            return
        }

        if parseLinkerLine(line) {
            return
        }

        if shouldParseBuildInfo {
            if parseDependencyGraph(line) {
                return
            }
            if let (phaseName, targetName) = parseBuildPhase(line) {
                addPhaseToTarget(phaseName, target: targetName)
                return
            }
            if let (phaseName, targetName) = parseSPMPhase(line) {
                addPhaseToTarget(phaseName, target: targetName)
                return
            }
            if let (targetName, duration) = parseTargetTiming(line) {
                if !targetOrder.contains(targetName) {
                    targetOrder.append(targetName)
                }
                targetDurations[targetName] = duration
                return
            }
        }

        // Fast path checks
        let containsRelevant =
            line.contains("error:") || line.contains("warning:") || line.contains("failed")
            || line.contains("passed")
            || line.contains("✘") || line.contains("✓") || line.contains("❌")
            || line.contains("Test ") || line.contains("recorded an issue")
            || line.contains("Build succeeded")
            || line.contains("Build failed") || line.contains("Executed")
            || line.contains("] Testing ")
            || line.contains("BUILD SUCCEEDED") || line.contains("BUILD FAILED")
            || line.contains("TEST FAILED")
            || line.contains("Build complete!")
            || line.hasPrefix("RegisterWithLaunchServices")
            || line.hasPrefix("Validate") || line.contains("Fatal error")
            || (line.hasPrefix("/") && line.contains(".swift:"))

        if !containsRelevant {
            return
        }

        // Parse parallel test scheduling: [N/TOTAL] Testing Module.Class/method
        if line.contains("] Testing ") {
            if let bracketStart = line.firstIndex(of: "["),
                let slashIndex = line[bracketStart...].firstIndex(of: "/"),
                let bracketEnd = line[slashIndex...].firstIndex(of: "]")
            {
                let numStr = line[line.index(after: bracketStart)..<slashIndex]
                let totalStr = line[line.index(after: slashIndex)..<bracketEnd]
                if Int(numStr) != nil, let total = Int(totalStr) {
                    if parallelTestsTotalCount == nil {
                        parallelTestsTotalCount = total
                    }
                }
            }
            return
        }

        // Parse executable registration
        if let executable = parseExecutable(line) {
            if seenExecutablePaths.insert(executable.path).inserted {
                executables.append(executable)
            }
            return
        }

        if let failedTest = parseFailedTest(line) {
            let normalizedTestName = normalizeTestName(failedTest.test)

            if !hasSeenSimilarTest(normalizedTestName) {
                failedTests.append(failedTest)
                seenTestNames.insert(normalizedTestName)
            } else {
                if let index = failedTests.firstIndex(where: {
                    normalizeTestName($0.test) == normalizedTestName
                }) {
                    let existing = failedTests[index]
                    let mergedFile = failedTest.file ?? existing.file
                    let mergedLine = failedTest.line ?? existing.line
                    let mergedMessage =
                        failedTest.file != nil ? failedTest.message : existing.message
                    let mergedDuration = failedTest.duration ?? existing.duration

                    if mergedFile != existing.file || mergedLine != existing.line
                        || mergedDuration != existing.duration
                    {
                        failedTests[index] = FailedTest(
                            test: existing.test,
                            message: mergedMessage,
                            file: mergedFile,
                            line: mergedLine,
                            duration: mergedDuration
                        )
                    }
                }
            }
        } else if let error = parseError(line) {
            let key = "\(error.file ?? ""):\(error.line ?? 0):\(error.message)"
            if !seenErrors.contains(key) {
                seenErrors.insert(key)
                errors.append(error)
            }
        } else if let warning = parseWarning(line) {
            let key = "\(warning.file ?? ""):\(warning.line ?? 0):\(warning.message)"
            if !seenWarnings.contains(key) {
                seenWarnings.insert(key)
                warnings.append(warning)
            }
        } else if let runtimeWarning = parseRuntimeWarning(line) {
            let key =
                "\(runtimeWarning.file ?? ""):\(runtimeWarning.line ?? 0):\(runtimeWarning.message)"
            if !seenWarnings.contains(key) {
                seenWarnings.insert(key)
                warnings.append(runtimeWarning)
            }
        } else if parsePassedTest(line) {
            return
        } else {
            parseBuildAndTestTime(line)
        }
    }

    // MARK: - Linker Error Parsing

    private func parseLinkerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("Undefined symbols for architecture ") {
            let afterPrefix = trimmed.dropFirst("Undefined symbols for architecture ".count)
            if let colonIndex = afterPrefix.firstIndex(of: ":") {
                currentLinkerArchitecture = String(afterPrefix[..<colonIndex])
            }
            return true
        }

        if trimmed.hasPrefix("\"") && trimmed.contains("\", referenced from:") {
            if let endQuote = trimmed.range(of: "\", referenced from:") {
                let symbol = String(
                    trimmed[trimmed.index(after: trimmed.startIndex)..<endQuote.lowerBound])
                pendingLinkerSymbol = symbol
            }
            return true
        }

        if let symbol = pendingLinkerSymbol, let arch = currentLinkerArchitecture,
            trimmed.contains(" in ") && (trimmed.hasSuffix(".o") || trimmed.hasSuffix(".a"))
        {
            if let inRange = trimmed.range(of: " in ") {
                let referencedFrom = String(trimmed[inRange.upperBound...])
                appendLinkerErrorIfNew(
                    LinkerError(symbol: symbol, architecture: arch, referencedFrom: referencedFrom)
                )
                pendingLinkerSymbol = nil
            }
            return true
        }

        if trimmed.hasPrefix("ld: framework not found ") {
            let framework = String(trimmed.dropFirst("ld: framework not found ".count))
            appendLinkerErrorIfNew(LinkerError(message: "framework not found \(framework)"))
            return true
        }

        if trimmed.hasPrefix("ld: library not found for ") {
            let library = String(trimmed.dropFirst("ld: library not found for ".count))
            appendLinkerErrorIfNew(LinkerError(message: "library not found for \(library)"))
            return true
        }

        if trimmed.hasPrefix("duplicate symbol '") || trimmed.hasPrefix("duplicate symbol \"") {
            let quoteChar: Character = trimmed.hasPrefix("duplicate symbol '") ? "'" : "\""
            let afterPrefix =
                trimmed.hasPrefix("duplicate symbol '")
                ? trimmed.dropFirst("duplicate symbol '".count)
                : trimmed.dropFirst("duplicate symbol \"".count)
            if let endQuote = afterPrefix.firstIndex(of: quoteChar) {
                pendingDuplicateSymbol = String(afterPrefix[..<endQuote])
                pendingConflictingFiles = []
            }
            return true
        }

        if pendingDuplicateSymbol != nil && (trimmed.hasSuffix(".o") || trimmed.hasSuffix(".a"))
            && (line.hasPrefix("    ") || line.hasPrefix("\t"))
        {
            pendingConflictingFiles.append(trimmed)
            return true
        }

        if trimmed.hasPrefix("ld: building for ") && trimmed.contains("but linking") {
            appendLinkerErrorIfNew(LinkerError(message: trimmed))
            return true
        }

        if trimmed.hasPrefix("ld: ") && trimmed.contains("duplicate symbol") {
            if let symbol = pendingDuplicateSymbol {
                var arch = ""
                if let archRange = trimmed.range(of: "for architecture ") {
                    arch = String(trimmed[archRange.upperBound...])
                }
                appendLinkerErrorIfNew(
                    LinkerError(
                        symbol: symbol, architecture: arch,
                        conflictingFiles: pendingConflictingFiles)
                )
                pendingDuplicateSymbol = nil
                pendingConflictingFiles = []
            }
            return true
        }

        if trimmed.hasPrefix("ld: symbol(s) not found for architecture ") {
            return true
        }

        return false
    }

    private func normalizeTestName(_ testName: String) -> String {
        if testName.hasPrefix("-[") && testName.hasSuffix("]") {
            return String(testName.dropFirst(2).dropLast(1))
        }
        return testName
    }

    /// Extracts a Swift Testing test name from a line containing `Test "name"` or `Test funcName()`.
    ///
    /// Returns the test name and the substring index after the name (past the closing quote or
    /// parentheses), or nil if no match.
    private func extractSwiftTestingName(from line: String, after startIndex: String.Index)
        -> (name: String, endIndex: String.Index)?
    {
        guard startIndex < line.endIndex else { return nil }

        // Quoted format: Test "name"
        if line[startIndex] == "\"" {
            let afterQuote = line.index(after: startIndex)
            guard afterQuote < line.endIndex,
                let closingQuote = line[afterQuote...].firstIndex(of: "\"")
            else {
                return nil
            }
            let name = String(line[afterQuote..<closingQuote])
            return (name, line.index(after: closingQuote))
        }

        // Unquoted format: Test funcName() ...
        // Find end by searching for known keyword markers that follow test names
        let afterTest = line[startIndex...]
        let endMarkers = [" recorded", " failed", " passed", " started"]
        for marker in endMarkers {
            if let markerRange = afterTest.range(of: marker) {
                let name = String(line[startIndex..<markerRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                return (name, markerRange.lowerBound)
            }
        }

        return nil
    }

    private func hasSeenSimilarTest(_ normalizedTestName: String) -> Bool {
        seenTestNames.contains(normalizedTestName)
    }

    private func appendLinkerErrorIfNew(_ error: LinkerError) {
        let key = "\(error.symbol):\(error.message)"
        if !seenLinkerErrors.contains(key) {
            seenLinkerErrors.insert(key)
            linkerErrors.append(error)
        }
    }

    private func isJSONLikeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("}")
            || trimmed.hasPrefix("]")
        {
            return true
        }

        if trimmed.hasPrefix("\"") && trimmed.contains("\" :") {
            return true
        }

        if line.contains("\\\"") && line.contains("\"") && line.contains(":") {
            return true
        }

        if line.hasPrefix(" ") || line.hasPrefix("\t") {
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("}") || trimmed.hasPrefix("[")
                || trimmed.hasPrefix("]")
            {
                return true
            }
            if trimmed.hasPrefix("\"") && trimmed.contains("\" :") {
                return true
            }
        }

        if line.contains("error:") {
            if trimmed.hasPrefix("\"") && trimmed.contains(":") {
                return true
            }
            if (line.hasPrefix(" ") || line.hasPrefix("\t")) && trimmed.hasPrefix("\"") {
                return true
            }
            if !trimmed.hasPrefix("error:") {
                let hasQuotedStrings = line.contains("\"") && line.contains(":")
                let hasEscapedContent = line.contains("\\") && line.contains("\"")
                if hasEscapedContent && hasQuotedStrings && !line.contains("file:")
                    && !line.contains(".swift:") && !line.contains(".m:")
                    && !line.contains(".h:")
                {
                    return true
                }
            }
        }

        return false
    }

    private func recordPassedTest(named testName: String, duration: Double? = nil) {
        let normalizedTestName = normalizeTestName(testName)
        guard seenPassedTestNames.insert(normalizedTestName).inserted else {
            return
        }
        passedTestsCount += 1

        if let dur = duration {
            passedTestDurations[normalizedTestName] = dur
        }
    }

    private func parseError(_ line: String) -> BuildError? {
        if isJSONLikeLine(line) {
            return nil
        }

        // Skip visual error lines
        if line.hasPrefix(" "), line.contains("|") || line.contains("`") {
            return nil
        }

        // Fast path: string parsing for ": error: "
        if let errorRange = line.range(of: ": error: ") {
            let beforeError = String(line[..<errorRange.lowerBound])
            let message = String(line[errorRange.upperBound...])

            let components = beforeError.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 3, let lineNum = Int(components[components.count - 2]),
                let colNum = Int(components[components.count - 1])
            {
                let file = components[0..<(components.count - 2)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message, column: colNum)
            } else if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0..<(components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message)
            } else {
                return BuildError(file: beforeError, line: nil, message: message)
            }
        }

        // Fatal error with message
        if let fatalRange = line.range(of: ": Fatal error: ") {
            let beforeError = String(line[..<fatalRange.lowerBound])
            let message = String(line[fatalRange.upperBound...])

            let components = beforeError.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0..<(components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message)
            } else {
                return BuildError(file: beforeError, line: nil, message: message)
            }
        }

        // Fatal error without trailing message
        if line.hasSuffix(": Fatal error"), !line.contains(" xctest[") {
            let beforeFatal = String(line.dropLast(": Fatal error".count))
            let components = beforeFatal.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0..<(components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: "Fatal error")
            }
        }

        if line.hasPrefix("❌ ") {
            let message = String(line.dropFirst(2))
            return BuildError(file: nil, line: nil, message: message)
        }

        if line.hasPrefix("error: ") {
            let message = String(line.dropFirst(7))
            return BuildError(file: nil, line: nil, message: message)
        }

        if line.contains("Command PhaseScriptExecution failed with a nonzero exit") {
            return BuildError(file: nil, line: nil, message: line)
        }

        return nil
    }

    private func parseWarning(_ line: String) -> BuildWarning? {
        if isJSONLikeLine(line) {
            return nil
        }

        if line.hasPrefix(" "), line.contains("|") || line.contains("`") {
            return nil
        }

        if let warningRange = line.range(of: ": warning: ") {
            let beforeWarning = String(line[..<warningRange.lowerBound])
            let message = String(line[warningRange.upperBound...])

            let components = beforeWarning.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 3, let lineNum = Int(components[components.count - 2]),
                let colNum = Int(components[components.count - 1])
            {
                let file = components[0..<(components.count - 2)].joined(separator: ":")
                return BuildWarning(
                    file: file, line: lineNum, message: message, column: colNum)
            } else if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0..<(components.count - 1)].joined(separator: ":")
                return BuildWarning(file: file, line: lineNum, message: message)
            } else {
                return BuildWarning(file: beforeWarning, line: nil, message: message)
            }
        }

        if line.hasPrefix("warning: ") {
            let message = String(line.dropFirst(9))
            return BuildWarning(file: nil, line: nil, message: message)
        }

        return nil
    }

    // MARK: - Runtime Warning Parsing

    private func parseRuntimeWarning(_ line: String) -> BuildWarning? {
        if line.contains(": warning:") || line.contains(": error:") {
            return nil
        }

        guard line.hasPrefix("/"), line.contains(".swift:") else {
            return nil
        }

        if line.contains("|") || line.contains("`-") {
            return nil
        }

        guard let swiftColonRange = line.range(of: ".swift:") else {
            return nil
        }

        let afterColon = line[swiftColonRange.upperBound...]

        var lineNumEnd = afterColon.startIndex
        while lineNumEnd < afterColon.endIndex, afterColon[lineNumEnd].isNumber {
            lineNumEnd = afterColon.index(after: lineNumEnd)
        }

        guard lineNumEnd > afterColon.startIndex,
            lineNumEnd < afterColon.endIndex,
            afterColon[lineNumEnd] == " "
        else {
            return nil
        }

        let lineNumStr = String(afterColon[..<lineNumEnd])
        guard let lineNum = Int(lineNumStr) else {
            return nil
        }

        let file = String(line[..<swiftColonRange.lowerBound]) + ".swift"
        let message = String(afterColon[afterColon.index(after: lineNumEnd)...])

        guard !message.isEmpty else {
            return nil
        }

        let type = detectRuntimeWarningType(message: message)
        return BuildWarning(file: file, line: lineNum, message: message, type: type)
    }

    private func detectRuntimeWarningType(message: String) -> WarningType {
        let swiftuiKeywords = [
            "Accessing Environment",
            "Accessing StateObject",
            "StateObject's wrappedValue",
            "Publishing changes from background",
            "Publishing changes from within view",
            "Modifying state during view update",
            "will always read the default value",
        ]

        if swiftuiKeywords.contains(where: { message.contains($0) }) {
            return .swiftui
        }

        return .runtime
    }

    private func parsePassedTest(_ line: String) -> Bool {
        let isStandardPassed = line.hasPrefix("Test Case '") && line.contains("' passed (")
        let isParallelPassed = line.hasPrefix("Test case '") && line.contains("' passed on '")

        if isStandardPassed || isParallelPassed {
            let prefixLength = 11  // "Test Case '" or "Test case '"
            let startIndex = line.index(line.startIndex, offsetBy: prefixLength)

            let passedPattern = isParallelPassed ? "' passed on '" : "' passed ("
            guard let endQuote = line.range(of: passedPattern) else { return false }
            let testName = String(line[startIndex..<endQuote.lowerBound])

            var duration: Double?
            if let lastParen = line.range(of: "(", options: .backwards),
                let secondsEnd = line.range(of: " seconds", options: .backwards)
            {
                let durationStr = String(line[lastParen.upperBound..<secondsEnd.lowerBound])
                duration = Double(durationStr)
            }

            recordPassedTest(named: testName, duration: duration)
            return true
        }

        // Swift Testing: <symbol> Test "name" passed or <symbol> Test funcName() passed
        if let testRange = line.range(of: "Test ") {
            let afterTest = line[testRange.upperBound...]
            // Skip "Test run with" (summary line) and "Test Case" (XCTest format)
            guard !afterTest.hasPrefix("run with "), !afterTest.hasPrefix("Case ") else {
                return false
            }
            let nameStart = testRange.upperBound
            if let extracted = extractSwiftTestingName(from: line, after: nameStart) {
                let remaining = line[extracted.endIndex...]
                if remaining.hasPrefix(" passed") {
                    var duration: Double?
                    if let afterRange = remaining.range(of: " after ") {
                        let afterStr = remaining[afterRange.upperBound...]
                        if let secondsRange = afterStr.range(of: " seconds") {
                            let durationStr = String(afterStr[..<secondsRange.lowerBound])
                            duration = Double(durationStr)
                        }
                    }
                    recordPassedTest(named: extracted.name, duration: duration)
                    return true
                }
            }
        }

        return false
    }

    private func parseFailedTest(_ line: String) -> FailedTest? {
        // XCUnit test failures
        if line.contains("XCTAssertEqual failed") || line.contains("XCTAssertTrue failed")
            || line.contains("XCTAssertFalse failed")
        {
            if let errorRange = line.range(of: ": error: -["),
                let bracketEnd = line.range(
                    of: "] : ", range: errorRange.upperBound..<line.endIndex)
            {
                let beforeError = String(line[..<errorRange.lowerBound])
                let testName = String(line[errorRange.upperBound..<bracketEnd.lowerBound])
                let message = String(line[bracketEnd.upperBound...])

                let components = beforeError.split(
                    separator: ":", omittingEmptySubsequences: false)
                if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                    let file = components[0..<(components.count - 1)].joined(separator: ":")
                    return FailedTest(
                        test: testName, message: message, file: file, line: lineNum)
                }
            }

            if let bracketStart = line.range(of: "-["),
                let bracketEnd = line.range(
                    of: "]", range: bracketStart.upperBound..<line.endIndex)
            {
                let testName = String(line[bracketStart.upperBound..<bracketEnd.lowerBound])
                return FailedTest(
                    test: testName,
                    message: line.trimmingCharacters(in: .whitespaces),
                    file: nil, line: nil
                )
            }

            return FailedTest(
                test: "Test assertion",
                message: line.trimmingCharacters(in: .whitespaces),
                file: nil, line: nil
            )
        }

        // Standard/Parallel: Test Case/case 'TestName' failed
        let isStandardFailed = line.hasPrefix("Test Case '") && line.contains("' failed (")
        let isParallelFailed = line.hasPrefix("Test case '") && line.contains("' failed on '")

        if isStandardFailed || isParallelFailed {
            let prefixLength = 11
            let startIndex = line.index(line.startIndex, offsetBy: prefixLength)

            let failedPattern = isParallelFailed ? "' failed on '" : "' failed ("
            guard let endQuote = line.range(of: failedPattern) else { return nil }
            let test = String(line[startIndex..<endQuote.lowerBound])

            var duration: Double?
            if let lastParen = line.range(of: "(", options: .backwards),
                let secondsEnd = line.range(of: " seconds", options: .backwards)
            {
                let durationStr = String(line[lastParen.upperBound..<secondsEnd.lowerBound])
                duration = Double(durationStr)
            }

            let normalizedTest = normalizeTestName(test)
            if let dur = duration {
                failedTestDurations[normalizedTest] = dur
            }

            let message = duration.map { String(format: "%.3f seconds", $0) } ?? "failed"
            return FailedTest(
                test: test, message: message, file: nil, line: nil, duration: duration)
        }

        // Swift Testing: <symbol> Test "name" recorded an issue at file:line:column: message
        // Also supports unquoted: <symbol> Test funcName() recorded an issue at ...
        if let testRange = line.range(of: "Test ") {
            let afterTest = line[testRange.upperBound...]
            // Skip "Test run with" (summary line) and "Test Case" (XCTest format)
            guard !afterTest.hasPrefix("run with "), !afterTest.hasPrefix("Case ") else {
                return nil
            }
            guard let extracted = extractSwiftTestingName(from: line, after: testRange.upperBound)
            else {
                return nil
            }
            let remaining = line[extracted.endIndex...]

            let issueMarker = " recorded an issue at "
            if remaining.hasPrefix(issueMarker) {
                let afterIssue = String(
                    remaining[remaining.index(remaining.startIndex, offsetBy: issueMarker.count)...]
                )
                let parts = afterIssue.split(
                    separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
                if parts.count >= 4, let lineNum = Int(parts[1]) {
                    let file = String(parts[0])
                    let message = String(parts[3]).trimmingCharacters(in: .whitespaces)
                    return FailedTest(
                        test: extracted.name, message: message, file: file, line: lineNum)
                }
            }

            let failedMarker = " failed after "
            if remaining.hasPrefix(failedMarker) {
                let afterStr = remaining[
                    remaining.index(remaining.startIndex, offsetBy: failedMarker.count)...]
                var duration: Double?
                if let secondsRange = afterStr.range(of: " seconds") {
                    let durationStr = String(afterStr[..<secondsRange.lowerBound])
                    duration = Double(durationStr)
                }

                let normalizedTest = normalizeTestName(extracted.name)
                if let dur = duration {
                    failedTestDurations[normalizedTest] = dur
                }

                return FailedTest(
                    test: extracted.name, message: "Test failed", file: nil, line: nil,
                    duration: duration)
            }
        }

        // ❌ testname (message)
        if line.hasPrefix("❌ "), let parenStart = line.range(of: " ("),
            let parenEnd = line.range(of: ")", options: .backwards)
        {
            let startIndex = line.index(line.startIndex, offsetBy: 2)
            let test = String(line[startIndex..<parenStart.lowerBound])
            let message = String(line[parenStart.upperBound..<parenEnd.lowerBound])
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }

        // testname (message) failed
        if line.hasSuffix(") failed") || line.hasSuffix(") failed."),
            let parenStart = line.range(of: " ("),
            let parenEnd = line.range(of: ") failed", options: .backwards)
        {
            let test = String(line[..<parenStart.lowerBound])
            let message = String(line[parenStart.upperBound..<parenEnd.lowerBound])
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }

        return nil
    }

    private func parseBuildAndTestTime(_ line: String) {
        if line.contains("** BUILD SUCCEEDED **") || line.contains("** BUILD FAILED **") {
            if let bracketStart = line.range(of: "[", options: .backwards),
                let bracketEnd = line.range(of: "]", options: .backwards),
                bracketStart.lowerBound < bracketEnd.lowerBound
            {
                buildTime = String(line[bracketStart.upperBound..<bracketEnd.lowerBound])
            }
            return
        }

        if line.contains("** TEST FAILED **") {
            testRunFailed = true
            return
        }

        if line.hasPrefix("Build complete!") {
            if let parenStart = line.range(of: "("),
                let parenEnd = line.range(of: ")"),
                parenStart.lowerBound < parenEnd.lowerBound
            {
                buildTime = String(line[parenStart.upperBound..<parenEnd.lowerBound])
            }
            return
        }

        if line.hasPrefix("Build succeeded in ") {
            buildTime = String(line.dropFirst(19))
            return
        }

        if line.hasPrefix("Build failed after ") {
            buildTime = String(line.dropFirst(19))
            return
        }

        // XCTest: Executed N tests, with N failures
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("Executed "), let withRange = trimmedLine.range(of: ", with ") {
            let afterExecuted = trimmedLine[
                trimmedLine.index(trimmedLine.startIndex, offsetBy: 9)..<withRange.lowerBound
            ]
            let testCountStr = afterExecuted.split(separator: " ").first
            if let testCountStr, let total = Int(testCountStr) {
                xctestExecutedCount = total
            }

            let afterWith = String(trimmedLine[withRange.upperBound...])
            if let failureRange = afterWith.range(of: " failure") {
                let beforeFailure = afterWith[..<failureRange.lowerBound]
                let words = beforeFailure.split(separator: " ")
                if let lastWord = words.last, let failures = Int(lastWord) {
                    xctestFailedCount = failures
                }
            }

            if let inRange = trimmedLine.range(
                of: " in ", range: withRange.upperBound..<trimmedLine.endIndex)
            {
                let afterIn = trimmedLine[inRange.upperBound...]
                if let parenStart = afterIn.range(of: " (") {
                    accumulateTestTime(String(afterIn[..<parenStart.lowerBound]))
                } else if let secondsRange = afterIn.range(of: " seconds", options: .backwards) {
                    accumulateTestTime(String(afterIn[..<secondsRange.lowerBound]))
                }
            }
            return
        }

        // Swift Testing failure summary (two formats):
        // Format 1: Test run with N tests failed, M tests passed after X seconds.
        // Format 2: Test run with N test(s) in M suite(s) failed after X seconds with Y issue(s).
        if let testRunRange = line.range(of: "Test run with ") {

            // Format 1: "N tests failed, M tests passed after X seconds."
            if let failedRange = line.range(
                of: " failed, ", range: testRunRange.upperBound..<line.endIndex),
                let passedRange = line.range(
                    of: " passed after ", range: failedRange.upperBound..<line.endIndex)
            {
                let beforeFailed = line[testRunRange.upperBound..<failedRange.lowerBound]
                let failedCountStr = beforeFailed.split(separator: " ").first
                if let failedCountStr, let failedCount = Int(failedCountStr) {
                    swiftTestingFailedCount = failedCount
                }

                let beforePassed = line[failedRange.upperBound..<passedRange.lowerBound]
                let passedCountStr = beforePassed.split(separator: " ").first
                if let passedCountStr, let passedCount = Int(passedCountStr),
                    let failedCount = swiftTestingFailedCount
                {
                    swiftTestingExecutedCount = passedCount + failedCount
                }

                let afterPassed = line[passedRange.upperBound...]
                if let secondsRange = afterPassed.range(of: " seconds", options: .backwards) {
                    accumulateTestTime(String(afterPassed[..<secondsRange.lowerBound]))
                } else {
                    accumulateTestTime(String(afterPassed))
                }
                return
            }

            // Format 2: "N test(s) in M suite(s) failed after X seconds with Y issue(s)."
            if let failedAfterRange = line.range(
                of: " failed after ", range: testRunRange.upperBound..<line.endIndex),
                line.contains(" issue")
            {
                let beforeFailed = line[testRunRange.upperBound..<failedAfterRange.lowerBound]
                let testCountStr = beforeFailed.split(separator: " ").first
                if let testCountStr, let total = Int(testCountStr) {
                    swiftTestingExecutedCount = total

                    // Extract issue count from "with Y issue(s)"
                    let afterFailed = line[failedAfterRange.upperBound...]
                    if let withRange = afterFailed.range(of: " with ") {
                        let afterWith = afterFailed[withRange.upperBound...]
                        let issueCountStr = afterWith.split(separator: " ").first
                        if let issueCountStr, let issueCount = Int(issueCountStr) {
                            swiftTestingFailedCount = issueCount
                        } else {
                            swiftTestingFailedCount = total
                        }
                    } else {
                        swiftTestingFailedCount = total
                    }

                    if let secondsRange = afterFailed.range(of: " seconds") {
                        let timeStr = String(afterFailed[..<secondsRange.lowerBound])
                        accumulateTestTime(timeStr)
                    }
                }
                return
            }

            // Swift Testing passed: Test run with N tests in M suites passed after X seconds.
            if let passedAfter = line.range(of: " passed after ") {
                let afterPrefix = line[testRunRange.upperBound..<passedAfter.lowerBound]
                let testCountStr = afterPrefix.split(separator: " ").first
                if let testCountStr, let total = Int(testCountStr) {
                    swiftTestingExecutedCount = total
                    swiftTestingFailedCount = 0

                    if total > 0 {
                        let afterPassed = line[passedAfter.upperBound...]
                        if let secondsRange = afterPassed.range(
                            of: " seconds", options: .backwards)
                        {
                            accumulateTestTime(String(afterPassed[..<secondsRange.lowerBound]))
                        } else {
                            accumulateTestTime(String(afterPassed))
                        }
                    }
                }
            }
        }
    }

    private func accumulateTestTime(_ timeString: String) {
        let cleaned = timeString.trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))
        if let time = Double(cleaned) {
            testTimeAccumulator += time
        }
    }

    // MARK: - Build Phase Parsing

    private func addPhaseToTarget(_ phase: String, target: String) {
        if targetPhases[target] == nil {
            targetPhases[target] = []
            if !targetOrder.contains(target) {
                targetOrder.append(target)
            }
        }
        if !targetPhases[target]!.contains(phase) {
            targetPhases[target]!.append(phase)
        }
    }

    private func extractTarget(from line: String) -> String? {
        if let inTargetRange = line.range(of: "(in target '") {
            let afterTarget = line[inTargetRange.upperBound...]
            if let endQuote = afterTarget.range(of: "'") {
                return String(afterTarget[..<endQuote.lowerBound])
            }
        }
        return nil
    }

    private static let phasePatterns: [(prefix: String, phaseName: String)] = [
        ("CompileSwiftSources ", "CompileSwiftSources"),
        ("CompileC ", "CompileC"),
        ("Ld ", "Link"),
        ("CopySwiftLibs ", "CopySwiftLibs"),
        ("PhaseScriptExecution ", "PhaseScriptExecution"),
        ("LinkAssetCatalog ", "LinkAssetCatalog"),
        ("ProcessInfoPlistFile ", "ProcessInfoPlistFile"),
    ]

    private func parseBuildPhase(_ line: String) -> (String, String)? {
        for (prefix, phaseName) in Self.phasePatterns {
            if line.hasPrefix(prefix), let target = extractTarget(from: line) {
                return (phaseName, target)
            }
        }

        if line.contains("SwiftDriver"), line.contains("Compilation"),
            let target = extractTarget(from: line)
        {
            return ("SwiftCompilation", target)
        }

        return nil
    }

    private func parseSPMPhase(_ line: String) -> (String, String)? {
        if line.contains("] Compiling ") {
            if let compilingRange = line.range(of: "] Compiling ") {
                let afterCompiling = line[compilingRange.upperBound...]
                let parts = afterCompiling.split(separator: " ", maxSplits: 1)
                if let targetName = parts.first {
                    let target = String(targetName)
                    if target == "plugin" {
                        return nil
                    }
                    return ("Compiling", target)
                }
            }
        }

        if line.contains("] Linking ") {
            if let linkingRange = line.range(of: "] Linking ") {
                let afterLinking = line[linkingRange.upperBound...]
                let targetName = afterLinking.trimmingCharacters(in: .whitespaces)
                if !targetName.isEmpty {
                    return ("Linking", targetName)
                }
            }
        }

        return nil
    }

    // MARK: - Dependency Graph Parsing

    private func parseDependencyGraph(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("Target '") && trimmed.contains("' in project '") {
            let afterTarget = trimmed.dropFirst("Target '".count)
            if let endQuote = afterTarget.range(of: "'") {
                let targetName = String(afterTarget[..<endQuote.lowerBound])
                currentDependencyTarget = targetName

                if !targetOrder.contains(targetName) {
                    targetOrder.append(targetName)
                }

                if trimmed.hasSuffix("(no dependencies)") {
                    targetDependencies[targetName] = []
                }
                return true
            }
        }

        if trimmed.contains("dependency on target '"), let currentTarget = currentDependencyTarget {
            if let startQuote = trimmed.range(of: "dependency on target '") {
                let afterStartQuote = trimmed[startQuote.upperBound...]
                if let endQuote = afterStartQuote.range(of: "'") {
                    let dependencyName = String(afterStartQuote[..<endQuote.lowerBound])

                    if targetDependencies[currentTarget] == nil {
                        targetDependencies[currentTarget] = []
                    }
                    if !targetDependencies[currentTarget]!.contains(dependencyName) {
                        targetDependencies[currentTarget]!.append(dependencyName)
                    }
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Target Timing Parsing

    private func parseTargetTiming(_ line: String) -> (String, String)? {
        if line.hasPrefix("Build target "), line.contains(" of project ") {
            let afterBuildTarget = line.dropFirst("Build target ".count)
            if let ofProjectRange = afterBuildTarget.range(of: " of project ") {
                let targetName = String(afterBuildTarget[..<ofProjectRange.lowerBound])

                if let parenStart = line.range(of: "(", options: .backwards),
                    let parenEnd = line.range(of: ")", options: .backwards),
                    parenStart.lowerBound < parenEnd.lowerBound
                {
                    let duration = String(line[parenStart.upperBound..<parenEnd.lowerBound])
                    return (targetName, duration)
                }
            }
        }

        if line.hasPrefix("Build target '"), line.contains("' completed") {
            let afterPrefix = line.dropFirst("Build target '".count)
            if let endQuote = afterPrefix.range(of: "'") {
                let targetName = String(afterPrefix[..<endQuote.lowerBound])

                if let parenStart = line.range(of: "(", options: .backwards),
                    let parenEnd = line.range(of: ")", options: .backwards),
                    parenStart.lowerBound < parenEnd.lowerBound
                {
                    let duration = String(line[parenStart.upperBound..<parenEnd.lowerBound])
                    return (targetName, duration)
                }
            }
        }

        return nil
    }

    // MARK: - Executable Parsing

    private func parseExecutable(_ line: String) -> Executable? {
        let prefixes = ["RegisterWithLaunchServices ", "Validate "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else {
            return nil
        }
        let afterPrefix = line.dropFirst(prefix.count)

        guard let targetRange = afterPrefix.range(of: " (in target '") else {
            return nil
        }

        let path = String(afterPrefix[..<targetRange.lowerBound])

        if !path.hasSuffix(".app") {
            return nil
        }

        let name = URL(fileURLWithPath: path).lastPathComponent

        let afterTarget = afterPrefix[targetRange.upperBound...]
        guard let targetEnd = afterTarget.range(of: "' from project") else {
            return nil
        }

        let target = String(afterTarget[..<targetEnd.lowerBound])

        return Executable(path: path, name: name, target: target)
    }
}
