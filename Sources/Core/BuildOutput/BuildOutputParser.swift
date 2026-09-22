// Adapted from xcsift (MIT License) - https://github.com/ldomaradzki/xcsift
import Foundation

/// Parses xcodebuild and swift build output into structured build results.
///
/// Extracts errors, warnings, linker errors, test failures, build timing, and code coverage from
/// raw build output text.
public final class BuildOutputParser {
    /// One `Executed N tests, with M failures` line from a single XCTest suite level.
    private struct XCTestTally {
        var executed = 0
        var failed = 0
        var time: Double = 0
        var seen = false
    }

    /// Everything one ``parse(input:coverage:slowThreshold:parseBuildInfo:)`` call accumulates.
    ///
    /// The state sits in a struct so a run starts from a fresh value rather than from a
    /// hand-written list of assignments. A property added here resets with the rest of them, which
    /// a second list cannot promise. The list this replaced had drifted: it cleared ``errors`` and
    /// left ``seenErrors`` holding the keys of the previous run, so a second parse on one instance
    /// reported none of the diagnostics the first one had seen.
    private struct ParserState {
        var errors: [BuildError] = []
        var warnings: [BuildWarning] = []
        var failedTests: [FailedTest] = []
        var linkerErrors: [LinkerError] = []
        var executables: [Executable] = []
        var seenExecutablePaths: Set<String> = []
        var buildTime: String?
        var testTimeAccumulator: Double = 0
        /// Normalized test name to its position in ``failedTests``
        ///
        /// A duplicate failure line merges into the entry it repeats. The lookup is by key so the
        /// merge does not rescan the array and normalize every name it walks.
        var failedTestIndexByName: [String: Int] = [:]
        var seenWarnings: Set<String> = []
        var seenErrors: Set<String> = []
        var seenLinkerErrors: Set<String> = []
        var xctestBundleTally = XCTestTally()
        var xctestOuterTally = XCTestTally()
        var currentSuiteName: String?
        var swiftTestingExecutedCount: Int?
        var swiftTestingFailedCount: Int?
        var swiftTestingKnownIssueCount: Int = 0
        /// The normalized name of every test a Swift Testing failure line named
        ///
        /// The run summary counts issues, and one test can record several. The size of this set is
        /// the count of distinct failing tests, which is the figure a reader expects.
        var swiftTestingFailedTestNames: Set<String> = []
        var passedTestsCount: Int = 0
        var seenPassedTestNames: Set<String> = []
        var parallelTestsTotalCount: Int?
        var testRunFailed: Bool = false

        // Terminal-marker tracking. xcodebuild/swift build always emit a terminal marker on a
        // complete run; their absence means the stream was truncated or the process was killed
        // (e.g. OOM `Killed: 9`) before finishing. We require positive evidence of success rather
        // than inferring it from the mere absence of failures — otherwise a killed build reads as a
        // false green.
        var sawTerminalSuccessMarker: Bool = false
        var sawTerminalFailureMarker: Bool = false

        /// Whether the line being read belongs to the source context echoed under a diagnostic
        /// header
        ///
        /// A compiler prints the offending source line under `file:line:col: error:`, indented,
        /// then a caret line under that. The echoed source can hold `: error: ` inside a string
        /// literal or a comment, and reading those bytes as a build error turns a green build red.
        /// See ``trackSourceEcho(_:)`` for the rules that open and close the block.
        var inSourceEchoBlock: Bool = false

        // Linker error parsing state
        var currentLinkerArchitecture: String?
        var pendingLinkerSymbol: String?

        // Duplicate symbol parsing state
        var pendingDuplicateSymbol: String?
        var pendingConflictingFiles: [String] = []

        // Crash-to-test association state
        var lastStartedTestName: String?
        var pendingSignalCode: Int?

        // Test duration tracking for slow/flaky detection
        var passedTestDurations: [String: Double] = [:]
        var failedTestDurations: [String: Double] = [:]

        // Performance measurement tracking
        var performanceMeasurements: [PerformanceMeasurement] = []

        // Build info tracking
        var targetPhases: [String: [String]] = [:]
        /// Mirrors ``targetPhases`` so the per-line parse tests membership without scanning the
        /// array
        var targetPhaseSet: [String: Set<String>] = [:]
        var targetDurations: [String: String] = [:]
        var targetOrder: [String] = []
        var targetOrderSet: Set<String> = []
        var shouldParseBuildInfo: Bool = false

        // Dependency graph tracking
        var targetDependencies: [String: [String]] = [:]
        /// Mirrors ``targetDependencies`` for the same reason as ``targetPhaseSet``
        var targetDependencySet: [String: Set<String>] = [:]
        var currentDependencyTarget: String?
    }

    /// The state of the run in progress. ``resetState()`` replaces it whole.
    private var state = ParserState()

    /// The XCTest counts for the run.
    ///
    /// XCTest repeats `Executed N tests` at each suite level: the nested suite, the `.xctest`
    /// bundle, and the `Selected tests` or `All tests` wrapper. Two `.xctest` bundles hold disjoint
    /// tests, so their counts add up. The levels around a bundle repeat the tests the bundle
    /// already reported, so adding them counts the same tests more than once. Prefer the bundle
    /// level, and fall back to the widest other line for output that never names a bundle.
    private var resolvedXCTestTally: XCTestTally? {
        state.xctestBundleTally.seen
            ? state.xctestBundleTally
            : state.xctestOuterTally.seen ? state.xctestOuterTally : nil
    }

    private var xctestExecutedCount: Int? { resolvedXCTestTally?.executed }

    private var xctestFailedCount: Int? { resolvedXCTestTally?.failed }

    /// Creates a parser holding no state.
    public init() {
        // Nothing to do. Every property starts from the default `ParserState` carries.
    }

    /// Parses build/test output into a structured `BuildResult`.
    public func parse(
        input: String,
        coverage: CodeCoverage? = nil,
        slowThreshold: Double? = nil,
        parseBuildInfo: Bool = false,
    ) -> BuildResult {
        resetState()
        state.shouldParseBuildInfo = parseBuildInfo
        let lines = BuildLogLines.split(input)

        for (index, line) in lines.enumerated() {
            parseLine(line)

            // Swift Testing: append custom #expect comments / multi-line messages macOS detail
            // symbol: 􀄵 (U+100135), Linux fallback: ↳ (U+21B3).
            //
            // Format (real swift-testing output): 􀢄 Test foo() recorded an issue at File.swift:1:1:
            // Issue recorded 􀄵 First line of Comment body second line of the same Comment (plain
            // indented continuation) third line 􀢄 Test foo() failed after 0.001 seconds with 1
            // issue.
            //
            // Only the first comment line carries the detail marker; subsequent lines of a
            // multi-line `Comment(rawValue:)` body are bare indented text. Stop when we hit a blank
            // line or another event line (non-indented, or starts with an SF Symbol private-use
            // marker).
            if line.contains("recorded an issue"), index + 1 < lines.count {
                var continuationParts: [String] = []
                var nextIdx = index + 1
                var sawDetailMarker = false

                while nextIdx < lines.count {
                    let raw = lines[nextIdx]
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { break }

                    if trimmed.hasPrefix("􀄵") || trimmed.hasPrefix("↳") {
                        let comment = String(
                            trimmed.drop(while: { $0 != " " }).drop(
                                while: { $0 == " " }
                            ))
                        if !comment.isEmpty { continuationParts.append(comment) }
                        sawDetailMarker = true
                        nextIdx += 1
                        continue
                    }

                    // Plain indented continuation of a multi-line Comment body. Only collect once
                    // we've seen at least one detail-marker line, and only when the line is
                    // indented (event lines start in column 0).
                    let firstChar = raw.first
                    let isIndented = firstChar == " " || firstChar == "\t"

                    if sawDetailMarker, isIndented, !isSwiftTestingEventLine(trimmed) {
                        continuationParts.append(trimmed)
                        nextIdx += 1
                        continue
                    }

                    break
                }
                if !continuationParts.isEmpty, let lastIdx = state.failedTests.indices.last {
                    let existing = state.failedTests[lastIdx]
                    state.failedTests[lastIdx] = FailedTest(
                        test: existing.test,
                        message: existing.message + "\n"
                            + continuationParts.joined(separator: "\n"),
                        file: existing.file,
                        line: existing.line,
                        duration: existing.duration,
                    )
                }
            }

            if line.contains("Command PhaseScriptExecution failed with a nonzero exit") {
                var contextLines: [String] = []
                let startIndex = max(0, index - 3)

                for contextIdx in startIndex..<index {
                    let contextLine = lines[contextIdx].trimmingCharacters(in: .whitespaces)

                    if contextLine.isEmpty || contextLine.hasPrefix("Warning:")
                        || contextLine.hasPrefix("Run script build phase") { continue }

                    if contextLine.contains(": warning:"), !contextLine.contains("error:") {
                        continue
                    }
                    contextLines.append(contextLine)
                }

                if !contextLines.isEmpty,
                   let lastIndex = state.errors.indices.last,
                   state.errors[lastIndex].message == line
                {
                    let combinedMessage = contextLines.joined(separator: " ") + " " + line
                    state.errors[lastIndex] = BuildError(
                        file: nil, line: nil, message: combinedMessage)
                }
            }
        }

        // Flush any duplicate-symbol block still pending (output truncated before ld's summary
        // line).
        flushPendingDuplicateSymbol()

        // Safety net: if a test started but never completed and the test run failed, record it as a
        // crash (ported from xcsift a1723d8)
        if state.testRunFailed, let testName = state.lastStartedTestName {
            let normalizedName = normalizeTestName(testName)

            if !hasSeenSimilarTest(normalizedName) {
                let message = state.pendingSignalCode.map {
                    "Crashed (signal \($0)): last test started before crash"
                } ?? "Test did not complete — possible crash"
                state.failedTestIndexByName[normalizedName] = state.failedTests.count
                state.failedTests.append(FailedTest(
                    test: testName, message: message, file: nil, line: nil,
                ))
            }
            state.lastStartedTestName = nil
            state.pendingSignalCode = nil
        }

        // Aggregate test counts from both XCTest and Swift Testing
        let totalExecuted: Int? = {
            if let parallelTotal = state.parallelTestsTotalCount {
                if let xctest = xctestExecutedCount { return parallelTotal + xctest }
                return parallelTotal
            }
            let xctest = xctestExecutedCount ?? 0
            let swiftTesting = state.swiftTestingExecutedCount ?? 0
            return xctest > 0 || swiftTesting > 0 ? xctest + swiftTesting : nil
        }()

        let totalFailed: Int = {
            let xctestFailed = xctestFailedCount ?? 0
            // A Swift Testing run summary counts issues, and one test can record several. The tests
            // its failure lines named are the better count. The summary count stands in when the
            // log named none, which is the truncated run.
            let swiftTestingFailed = state.swiftTestingFailedTestNames.isEmpty
                ? state.swiftTestingFailedCount ?? 0
                : state.swiftTestingFailedTestNames.count
            let aggregated = xctestFailed + swiftTestingFailed
            return aggregated > 0 ? aggregated : state.failedTests.count
        }()

        let computedPassedTests: Int? = {
            if let executed = totalExecuted { return max(executed - totalFailed, 0) }
            return state.passedTestsCount > 0 ? state.passedTestsCount : nil
        }()

        let status: String = {
            // Reconcile with the aggregate failure count so `status` can never disagree with
            // `summary.failedTests`: a failure that surfaces only in the "Executed N tests, with M
            // failures" line (e.g. KIF exceptions, aggregated parallel output) — never as an
            // individual "Test Case … failed" line — must still fail the run.
            let hasActualFailures = !state.errors.isEmpty || !state.failedTests.isEmpty
                || !state.linkerErrors.isEmpty || totalFailed > 0
            let hasPassedTests = (computedPassedTests ?? 0) > 0
            let sawFailureMarker = state.sawTerminalFailureMarker || state.testRunFailed

            // Concrete failures always fail the run.
            return hasActualFailures
                ? "failed"
                : sawFailureMarker
                    ? hasPassedTests ? "success" : "failed"
                    : state.sawTerminalSuccessMarker || hasPassedTests ? "success" : "incomplete"
        }()

        let slowTests: [SlowTest] = {
            guard let threshold = slowThreshold else { return [] }
            return detectSlowTests(threshold: threshold)
        }()

        let flakyTests = detectFlakyTests()

        // The XCTest duration comes from the same suite level as the XCTest counts, so a repeated
        // level never adds its seconds a second time.
        let totalTestTime = state.testTimeAccumulator + (resolvedXCTestTally?.time ?? 0)

        let formattedTestTime: String? = totalTestTime > 0
            ? String(format: "%.3fs", totalTestTime)
            : nil

        let summary = BuildSummary(
            errors: state.errors.count,
            warnings: state.warnings.count,
            failedTests: totalFailed,
            linkerErrors: state.linkerErrors.count,
            passedTests: computedPassedTests,
            buildTime: state.buildTime,
            testTime: formattedTestTime,
            coveragePercent: coverage?.lineCoverage,
            slowTests: slowTests.isEmpty ? nil : slowTests.count,
            flakyTests: flakyTests.isEmpty ? nil : flakyTests.count,
            executables: state.executables.isEmpty ? nil : state.executables.count,
            knownIssues: state.swiftTestingKnownIssueCount > 0
                ? state.swiftTestingKnownIssueCount
                : nil,
        )

        let buildInfo: BuildInfo? = parseBuildInfo
            ? {
                let targets = state.targetOrder.map { targetName in
                    TargetBuildInfo(
                        name: targetName,
                        duration: state.targetDurations[targetName],
                        phases: state.targetPhases[targetName] ?? [],
                        dependsOn: state.targetDependencies[targetName] ?? [],
                    )
                }
                let slowestTargets = computeSlowestTargets(targets: targets, limit: 5)
                return BuildInfo(targets: targets, slowestTargets: slowestTargets)
            }()
            : nil

        return .init(
            status: status,
            summary: summary,
            errors: state.errors,
            warnings: state.warnings,
            failedTests: state.failedTests,
            linkerErrors: state.linkerErrors,
            coverage: coverage,
            slowTests: slowTests,
            flakyTests: flakyTests,
            buildInfo: buildInfo,
            executables: state.executables,
            performanceMeasurements: state.performanceMeasurements,
        )
    }

    // MARK: - Slow/Flaky Test Detection

    private func detectSlowTests(threshold: Double) -> [SlowTest] {
        var slow: [SlowTest] = []
        var seenNames: Set<String> = []

        for (name, duration) in state.passedTestDurations where duration > threshold {
            slow.append(SlowTest(test: name, duration: duration))
            seenNames.insert(name)
        }

        for (name, duration) in state.failedTestDurations where duration > threshold {
            if !seenNames.contains(name) { slow.append(SlowTest(test: name, duration: duration)) }
        }

        return slow.sorted { $0.duration > $1.duration }
    }

    private func detectFlakyTests() -> [String] {
        let passedNames = Set(state.passedTestDurations.keys)
        let failedNames = Set(state.failedTestIndexByName.keys)
        return Array(passedNames.intersection(failedNames)).sorted()
    }

    private func computeSlowestTargets(targets: [TargetBuildInfo], limit: Int) -> [String] {
        func parseDuration(_ duration: String?) -> Double {
            guard let d = duration, d.hasSuffix("s") else { return 0 }
            return Double(d.dropLast()) ?? 0
        }

        // parse once per target, not twice per comparison
        let sorted = targets.lazy
            .compactMap { $0.duration == nil ? nil : ($0.name, parseDuration($0.duration)) }
            .sorted { $0.1 > $1.1 }

        return sorted.prefix(limit).map(\.0)
    }

    /// Discards the previous run, so one parser instance can read a second log.
    ///
    /// Assigning a fresh ``ParserState`` resets every property it holds. A list of per-property
    /// assignments stood here before, and it had already fallen behind the properties it was meant
    /// to cover.
    private func resetState() { state = ParserState() }

    private func parseLine(_ line: String) {
        // Bytes, not characters: `count` walks the whole line to break graphemes, and this runs on
        // every line of a log that can reach 100 MB. The cap is a sanity bound either way.
        if line.utf8.count > 5000 { return }

        // Runs ahead of every branch below, so the echo block closes on the line that ends it
        // whichever parser consumes that line.
        let insideSourceEcho = trackSourceEcho(line)

        if line.isEmpty { return }

        // XCTest names the suite before the `Executed` line that reports it, so the most recent
        // name tells us which level those counts belong to. Read it before any branch returns,
        // because a suite result line also matches the passed-test and failed-test parsers.
        if line.hasPrefix("Test Suite '") {
            let afterQuote = line.dropFirst("Test Suite '".count)

            if let endQuote = afterQuote.firstIndex(of: "'") {
                state.currentSuiteName = String(afterQuote[..<endQuote])
            }
        }

        if parseLinkerLine(line) { return }

        if state.shouldParseBuildInfo {
            if parseDependencyGraph(line) { return }

            if let (phaseName, targetName) = parseBuildPhase(line) {
                addPhaseToTarget(phaseName, target: targetName)
                return
            }
            if let (phaseName, targetName) = parseSPMPhase(line) {
                addPhaseToTarget(phaseName, target: targetName)
                return
            }
            if let (targetName, duration) = parseTargetTiming(line) {
                if state.targetOrderSet.insert(targetName).inserted {
                    state.targetOrder.append(targetName)
                }
                state.targetDurations[targetName] = duration
                return
            }
        }

        // Performance measurements: "measured [Time, seconds] average: ..."
        if line.contains("measured [") {
            parsePerformanceMeasurement(line)
            return
        }

        // Fast path checks
        let containsRelevant = line.contains("error:") || line.contains("warning:")
            || line.contains("failed")
            || line.contains("passed")
            || line.contains("✘") || line.contains("✓") || line.contains("❌")
            || line.contains("Test ") || line.contains("recorded an issue")
            || line.contains("Build succeeded")
            || line.contains("Build failed") || line.contains("Executed")
            || line.contains("] Testing ")
            // Any `** <PHASE> SUCCEEDED **` or `** <PHASE> FAILED **` marker, fenced or rewritten
            // by xcbeautify in title case.
            || line.contains("SUCCEEDED") || line.contains("FAILED")
            || line.contains("Succeeded") || line.contains("Failed")
            || line.contains("Build complete!")
            || line.hasPrefix("RegisterWithLaunchServices")
            || line.hasPrefix("Validate") || line.contains("Fatal error")
            || line.contains("signal code") || line.contains("Restarting after")
            || line.contains("started")
            || (line.hasPrefix("/") && line.contains(".swift:"))

        if !containsRelevant { return }

        // Parse parallel test scheduling: [N/TOTAL] Testing Module.Class/method
        if line.contains("] Testing ") {
            if let bracketStart = line.firstIndex(of: "["),
               let slashIndex = line[bracketStart...].firstIndex(of: "/"),
               let bracketEnd = line[slashIndex...].firstIndex(of: "]")
            {
                let numStr = line[line.index(after: bracketStart)..<slashIndex]
                let totalStr = line[line.index(after: slashIndex)..<bracketEnd]

                if let num = Int(numStr), let total = Int(totalStr) {
                    if state.parallelTestsTotalCount == nil {
                        state.parallelTestsTotalCount = total
                    } else if num == 1 {
                        // New parallel run started — accumulate
                        state.parallelTestsTotalCount = (state.parallelTestsTotalCount ?? 0) + total
                    }
                }
            }
            return
        }

        // Parse executable registration
        if let executable = parseExecutable(line) {
            if state.seenExecutablePaths.insert(executable.path).inserted {
                state.executables.append(executable)
            }
            return
        }

        // Track test starts for crash association
        if let startedName = parseStartedTest(line) {
            state.lastStartedTestName = startedName
            return
        }

        // Detect crash signal codes
        if line.contains("signal code") {
            if let lastSpace = line.lastIndex(of: " ") {
                let codeStr = String(line[line.index(after: lastSpace)...])
                state.pendingSignalCode = Int(codeStr)
            }
            return
        }

        // Crash confirmation — associate with last started test
        if line.contains("Restarting after"), let testName = state.lastStartedTestName {
            let normalizedName = normalizeTestName(testName)

            if !hasSeenSimilarTest(normalizedName) {
                let message = state.pendingSignalCode.map {
                    "Crashed (signal \($0)): last test started before crash"
                } ?? "Crashed: last test started before crash"
                state.failedTestIndexByName[normalizedName] = state.failedTests.count
                state.failedTests.append(FailedTest(
                    test: testName, message: message, file: nil, line: nil,
                ))
            }
            state.lastStartedTestName = nil
            state.pendingSignalCode = nil
            return
        }

        if let failedTest = parseFailedTest(line) {
            let normalizedTestName = normalizeTestName(failedTest.test)

            if !hasSeenSimilarTest(normalizedTestName) {
                state.failedTestIndexByName[normalizedTestName] = state.failedTests.count
                state.failedTests.append(failedTest)
            } else {
                if let index = state.failedTestIndexByName[normalizedTestName] {
                    let existing = state.failedTests[index]
                    let mergedFile = failedTest.file ?? existing.file
                    let mergedLine = failedTest.line ?? existing.line
                    let mergedMessage = failedTest.file != nil
                        ? failedTest.message
                        : existing.message
                    let mergedDuration = failedTest.duration ?? existing.duration

                    if mergedFile != existing.file || mergedLine != existing.line
                        || mergedDuration != existing.duration
                    {
                        state.failedTests[index] = FailedTest(
                            test: existing.test,
                            message: mergedMessage,
                            file: mergedFile,
                            line: mergedLine,
                            duration: mergedDuration,
                        )
                    }
                }
            }
            state.lastStartedTestName = nil
        } else if !insideSourceEcho, let error = parseError(line) {
            appendErrorIfNew(error)
        } else if !insideSourceEcho, let warning = parseWarning(line) {
            appendWarningIfNew(warning)
        } else if !insideSourceEcho, let runtimeWarning = parseRuntimeWarning(line) {
            appendWarningIfNew(runtimeWarning)
        } else if parsePassedTest(line) {
            return
        } else {
            parseBuildAndTestTime(line)
        }
    }

    // MARK: - Source Context Echo

    /// The keywords a compiler puts between the source location and the diagnostic message.
    private static let diagnosticKeywords = [": error: ", ": warning: ", ": note: "]

    /// Advances the source-context echo state by one line and reports whether that line is echoed
    /// source rather than a diagnostic of its own.
    ///
    /// A compiler prints a diagnostic as a header, the offending source line indented under it, and
    /// a caret line under that:
    ///
    /// ```
    /// /Sources/Log.swift:12:20: error: cannot find 'foo' in scope
    ///     let banner = ": error: not a real one"
    ///                  ^
    /// ```
    ///
    /// Reading the echoed line as a build error turns a successful build into a failed one. The
    /// rules:
    ///
    /// - A located header opens a block. It also closes any block still open, so two headers in a
    ///   row are both reported. Xcode's own build log indents its headers under the task that
    ///   emitted them, which would otherwise read as echoed source of the header above.
    /// - The block closes on the caret line, or on the first line that carries no indentation.
    /// - Indentation alone never suppresses a diagnostic. An indented
    ///   `swiftgen: error: template not found` and an indented
    ///   `Command PhaseScriptExecution failed with a nonzero exit code` stay reportable, because
    ///   neither follows a located header.
    ///
    /// - Parameter line: The line being read, with its indentation intact.
    /// - Returns: `true` when the line is echoed source, so the diagnostic parsers skip it.
    private func trackSourceEcho(_ line: String) -> Bool {
        if Self.isLocatedDiagnosticHeader(line) {
            state.inSourceEchoBlock = true
            return false
        }
        guard state.inSourceEchoBlock else { return false }
        guard Self.isIndented(line) else {
            state.inSourceEchoBlock = false
            return false
        }
        // The caret line belongs to the block and ends it.
        if Self.isCaretLine(line) { state.inSourceEchoBlock = false }
        return true
    }

    /// Whether `line` starts with a space or a tab.
    private static func isIndented(_ line: String) -> Bool {
        guard let first = line.utf8.first else { return false }
        return first == UInt8(ascii: " ") || first == UInt8(ascii: "\t")
    }

    /// Whether `line` is the caret line a compiler prints under the echoed source.
    ///
    /// Such a line holds nothing but whitespace, `^` and `~`, and at least one `^`.
    private static func isCaretLine(_ line: String) -> Bool {
        var sawCaret = false

        for byte in line.utf8 {
            switch byte {
                case UInt8(ascii: "^"): sawCaret = true
                case UInt8(ascii: "~"), UInt8(ascii: " "), UInt8(ascii: "\t"): continue
                default: return false
            }
        }
        return sawCaret
    }

    /// Whether `line` is a diagnostic header that names a source location.
    ///
    /// Only a located header is followed by an echo of the source. A header without one, such as
    /// `error: no such module 'Foo'`, prints no source line and opens no block.
    ///
    /// The location must carry no space, which is what separates a real header from an echoed
    /// source line that quotes one. A project path that holds a space fails this test. The
    /// diagnostic on that line is still reported; only the echo under it goes untracked.
    private static func isLocatedDiagnosticHeader(_ line: String) -> Bool {
        guard let keywordStart = firstDiagnosticKeyword(in: line) else { return false }
        let location = line[..<keywordStart].drop { $0 == " " || $0 == "\t" }
        guard !location.isEmpty, !location.contains(where: { $0 == " " }) else { return false }
        // `<path>:<line>` and `<path>:<line>:<column>` both qualify, so the last component is the
        // one that has to be a number.
        let components = location.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count >= 2, let last = components.last else { return false }
        return Int(last) != nil
    }

    /// The start of the earliest diagnostic keyword on `line`, or `nil` when it carries none.
    ///
    /// This runs on every line of a build log that can reach 100 MB, and most of those lines are
    /// build commands carrying no keyword at all. One scan for `":"` rejects them, so the common
    /// line costs a single pass rather than one pass per keyword.
    private static func firstDiagnosticKeyword(in line: String) -> String.Index? {
        guard line.utf8.contains(UInt8(ascii: ":")) else { return nil }
        var earliest: String.Index?

        for keyword in diagnosticKeywords {
            guard let range = line.range(of: keyword) else { continue }
            if let found = earliest, found <= range.lowerBound { continue }
            earliest = range.lowerBound
        }
        return earliest
    }

    // MARK: - Linker Error Parsing

    private func parseLinkerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("Undefined symbols for architecture ") {
            let afterPrefix = trimmed.dropFirst("Undefined symbols for architecture ".count)

            if let colonIndex = afterPrefix.firstIndex(of: ":") {
                state.currentLinkerArchitecture = String(afterPrefix[..<colonIndex])
            }
            return true
        }

        if trimmed.hasPrefix("\""), trimmed.contains("\", referenced from:") {
            if let endQuote = trimmed.range(of: "\", referenced from:") {
                let symbol = String(
                    trimmed[trimmed.index(after: trimmed.startIndex)..<endQuote.lowerBound],
                )
                state.pendingLinkerSymbol = symbol
            }
            return true
        }

        if let symbol = state.pendingLinkerSymbol,
           let arch = state.currentLinkerArchitecture,
           trimmed.contains(" in "),
           trimmed.hasSuffix(".o") || trimmed.hasSuffix(".a")
        {
            if let inRange = trimmed.range(of: " in ") {
                let referencedFrom = String(trimmed[inRange.upperBound...])
                appendLinkerErrorIfNew(LinkerError(
                    symbol: symbol, architecture: arch, referencedFrom: referencedFrom))
                state.pendingLinkerSymbol = nil
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
            // ld lists each duplicate symbol as its own `duplicate symbol 'X' in:` block before the
            // trailing `ld: N duplicate symbols` summary. A new header therefore closes the
            // previous block — flush it so multiple duplicates aren't collapsed into just the last
            // one.
            flushPendingDuplicateSymbol()

            let quoteChar: Character = trimmed.hasPrefix("duplicate symbol '") ? "'" : "\""
            let afterPrefix = trimmed.hasPrefix("duplicate symbol '")
                ? trimmed.dropFirst("duplicate symbol '".count)
                : trimmed.dropFirst("duplicate symbol \"".count)

            if let endQuote = afterPrefix.firstIndex(of: quoteChar) {
                state.pendingDuplicateSymbol = String(afterPrefix[..<endQuote])
                state.pendingConflictingFiles = []
            }
            return true
        }

        // Every indented, non-empty line under a duplicate-symbol header is one of the files that
        // redefines the symbol. ld emits object files (`.o`/`.a`), framework binaries
        // (`.../Foo.framework/Versions/A/Foo`), dylibs, and the literal `bundle-file` here, so
        // collect by indentation rather than filtering on a file extension (the old `.o`/`.a`-only
        // check dropped framework/bundle paths, leaving the error looking like an undefined
        // symbol).
        if state.pendingDuplicateSymbol != nil,
           line.hasPrefix("    ") || line.hasPrefix("\t"),
           !trimmed.isEmpty
        {
            state.pendingConflictingFiles.append(trimmed)
            return true
        }

        if trimmed.hasPrefix("ld: building for "), trimmed.contains("but linking") {
            appendLinkerErrorIfNew(LinkerError(message: trimmed))
            return true
        }

        if trimmed.hasPrefix("ld: "), trimmed.contains("duplicate symbol") {
            var arch = ""

            if let archRange = trimmed.range(of: "for architecture ") {
                arch = String(trimmed[archRange.upperBound...])
            }
            flushPendingDuplicateSymbol(architecture: arch)
            return true
        }

        return trimmed.hasPrefix("ld: symbol(s) not found for architecture ") ? true : false
    }

    /// Returns true if a trimmed line looks like a swift-testing event line (starts with one of the
    /// SF Symbol private-use markers swift-testing emits for run/test/issue events: 􀟈, 􀟉, 􀢄, 􀢇, 􀦗,
    /// 􁁛, 􁁒, etc.) or with the ASCII fallback `✘`/`✓`/`◇`/`↳`. We can't enumerate every glyph, so
    /// we check whether the first scalar lives in the SF Symbols private-use ranges.
    private func isSwiftTestingEventLine(_ trimmed: String) -> Bool {
        guard let first = trimmed.unicodeScalars.first else { return false }
        // SF Symbols private-use range used by swift-testing markers
        return (0xE000...0xF8FF).contains(first.value)
            || (0xF0000...0xFFFFD).contains(first.value)
            || (0x100000...0x10FFFD).contains(first.value)
            ? true
            : first == "✘" || first == "✓" || first == "◇"
    }

    private func normalizeTestName(_ testName: String) -> String {
        var name = testName

        if name.hasPrefix("-["), name.hasSuffix("]") {
            name = String(name.dropFirst(2).dropLast(1))
        }
        // Strip parameterized argument suffix (→ ...) for deduplication
        if let parenRange = name.range(of: " (→ ", options: .backwards) {
            name = String(name[..<parenRange.lowerBound])
        }
        return name
    }

    /// Extracts a Swift Testing test name from a line containing `Test "name"` or
    /// `Test funcName()`.
    ///
    /// Returns the test name and the substring index after the name (past the closing quote or
    /// parentheses and any trailing modifiers like `(aka '...')` or `with N test case(s)`), or nil
    /// if no match.
    private func extractSwiftTestingName(
        from line: String,
        after startIndex: String.Index
    ) -> (name: String, endIndex: String.Index)? {
        guard startIndex < line.endIndex else { return nil }

        // Quoted format: Test "name"
        if line[startIndex] == "\"" {
            let afterQuote = line.index(after: startIndex)
            guard afterQuote < line.endIndex,
                  let closingQuote = line[afterQuote...].firstIndex(of: "\"") else { return nil }
            let name = String(line[afterQuote..<closingQuote])
            var endIndex = line.index(after: closingQuote)

            // Skip optional (aka '...') verbose suffix
            let afterName = line[endIndex...]

            if afterName.hasPrefix(" (aka '"),
               let closeRange = afterName.range(of: "')") { endIndex = closeRange.upperBound }

            // Skip optional "with N test case(s)" parameterized suffix
            let afterModifiers = line[endIndex...]

            if afterModifiers.hasPrefix(" with "),
               let caseRange = afterModifiers.range(of: " test case")
            {
                var idx = caseRange.upperBound
                if idx < line.endIndex, line[idx] == "s" { idx = line.index(after: idx) }
                endIndex = idx
            }

            return (name, endIndex)
        }

        // Unquoted format: Test funcName() ... Find end by searching for known keyword markers that
        // follow test names
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
        state.failedTestIndexByName[normalizedTestName] != nil
    }

    private func appendLinkerErrorIfNew(_ error: LinkerError) {
        // Include the kind so an undefined and a duplicate error for the same symbol name don't
        // collapse into one — they are opposite diagnoses.
        let key = "\(error.kind.rawValue):\(error.symbol):\(error.message)"

        if !state.seenLinkerErrors.contains(key) {
            state.seenLinkerErrors.insert(key)
            state.linkerErrors.append(error)
        }
    }

    /// Emits the pending duplicate-symbol error (with whatever defining files were collected) and
    /// clears the pending state. No-op when nothing is pending.
    private func flushPendingDuplicateSymbol(architecture: String = "") {
        guard let symbol = state.pendingDuplicateSymbol else { return }
        appendLinkerErrorIfNew(LinkerError(
            symbol: symbol, architecture: architecture,
            conflictingFiles: state.pendingConflictingFiles,
        ))
        state.pendingDuplicateSymbol = nil
        state.pendingConflictingFiles = []
    }

    private func appendErrorIfNew(_ error: BuildError) {
        let key = "\(error.file ?? ""):\(error.line ?? 0):\(error.message)"

        if !state.seenErrors.contains(key) {
            state.seenErrors.insert(key)
            state.errors.append(error)
        }
    }

    private func appendWarningIfNew(_ warning: BuildWarning) {
        let key = "\(warning.file ?? ""):\(warning.line ?? 0):\(warning.message)"

        if !state.seenWarnings.contains(key) {
            state.seenWarnings.insert(key)
            state.warnings.append(warning)
        }
    }

    private func isJSONLikeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("}")
            || trimmed.hasPrefix("]") { return true }

        if trimmed.hasPrefix("\""), trimmed.contains("\" :") { return true }

        if line.contains("\\\""), line.contains("\""), line.contains(":") { return true }

        if line.hasPrefix(" ") || line.hasPrefix("\t") {
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("}") || trimmed.hasPrefix("[")
                || trimmed.hasPrefix("]") { return true }
            if trimmed.hasPrefix("\""), trimmed.contains("\" :") { return true }
        }

        if line.contains("error:") {
            if trimmed.hasPrefix("\""), trimmed.contains(":") { return true }
            if line.hasPrefix(" ") || line.hasPrefix("\t"), trimmed.hasPrefix("\"") { return true }

            if !trimmed.hasPrefix("error:") {
                let hasQuotedStrings = line.contains("\"") && line.contains(":")
                let hasEscapedContent = line.contains("\\") && line.contains("\"")

                if hasEscapedContent,
                   hasQuotedStrings,
                   !line.contains("file:"),
                   !line.contains(".swift:"),
                   !line.contains(".m:"),
                   !line.contains(".h:") { return true }
            }
        }

        return false
    }

    private func recordPassedTest(named testName: String, duration: Double? = nil) {
        let normalizedTestName = normalizeTestName(testName)
        guard state.seenPassedTestNames.insert(normalizedTestName).inserted else { return }
        state.passedTestsCount += 1
        state.lastStartedTestName = nil

        if let dur = duration { state.passedTestDurations[normalizedTestName] = dur }
    }

    /// Extracts a test name from "started" lines (XCTest and Swift Testing formats).
    private func parseStartedTest(_ line: String) -> String? {
        // XCTest: Test Case '-[Module.Class testMethod]' started. Also: Test Case
        // 'Module.Class.testMethod' started.
        if line.hasPrefix("Test Case '"), line.hasSuffix("' started.") {
            let prefixLength = 11  // "Test Case '"
            let suffixLength = 10  // "' started."
            let startIndex = line.index(line.startIndex, offsetBy: prefixLength)
            let endIndex = line.index(line.endIndex, offsetBy: -suffixLength)
            guard startIndex < endIndex else { return nil }
            return String(line[startIndex..<endIndex])
        }

        // Swift Testing: ◇ Test "name" started. Also: ◇ Test funcName() started.
        if line.contains("Test "), line.hasSuffix(" started.") {
            if let testRange = line.range(of: "Test ") {
                let nameStart = testRange.upperBound
                guard !line[nameStart...].hasPrefix("run with "),
                      !line[nameStart...].hasPrefix("Case ") else { return nil }

                if let extracted = extractSwiftTestingName(from: line, after: nameStart) {
                    let remaining = line[extracted.endIndex...]
                    if remaining == " started." { return extracted.name }
                }
            }
        }

        return nil
    }

    /// A path recovered from a diagnostic line, without the indentation in front of it.
    ///
    /// Xcode's own build log indents a diagnostic under the task that emitted it. The indentation
    /// would otherwise land inside the recovered path, and the caller would report a file that
    /// nothing can open.
    private static func trimmedPath(_ path: some StringProtocol) -> String {
        String(path.drop { $0 == " " || $0 == "\t" })
    }

    /// The file, line and column a diagnostic prefix names.
    ///
    /// The prefix is everything on the line before the keyword, such as `: error: `. It takes three
    /// shapes, and each falls back to the next:
    ///
    /// - `<path>:<line>:<column>`
    /// - `<path>:<line>`
    /// - a bare `<path>`, when neither trailing component reads as a number
    ///
    /// The indentation comes off once here, so every shape reports a path that can be opened and no
    /// caller has to remember the trim.
    ///
    /// - Parameter prefix: The text before the diagnostic keyword.
    /// - Returns: The path, plus the line and column when the prefix names them.
    private static func sourceLocation(
        in prefix: some StringProtocol,
    ) -> (file: String, line: Int?, column: Int?) {
        let trimmed = trimmedPath(prefix)
        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false)

        if components.count >= 3,
           let lineNumber = Int(components[components.count - 2]),
           let column = Int(components[components.count - 1]) {
            return (components.dropLast(2).joined(separator: ":"), lineNumber, column)
        }

        if components.count >= 2, let lineNumber = Int(components[components.count - 1]) {
            return (components.dropLast().joined(separator: ":"), lineNumber, nil)
        }
        return (trimmed, nil, nil)
    }

    /// A test duration in seconds, or `nil` when the text names no finite number.
    ///
    /// XCTest prints `failed (inf seconds)` for a test whose clock produced no usable figure, and
    /// `Double("inf")` turns that into an infinity. `JSONEncoder` refuses a non-finite double, so
    /// one such line would fail the encoding of the whole result rather than of the one test.
    /// Dropping the value leaves the test reported with no duration.
    ///
    /// - Parameter text: The seconds figure, with any surrounding whitespace.
    private static func parseSeconds(_ text: some StringProtocol) -> Double? {
        guard let seconds = Double(text.trimmingCharacters(in: .whitespaces)), seconds.isFinite
        else { return nil }
        return seconds
    }

    private func parseError(_ line: String) -> BuildError? {
        if isJSONLikeLine(line) { return nil }

        // Skip visual error lines
        if line.hasPrefix(" "), line.contains("|") || line.contains("`") { return nil }

        // Fast path: string parsing for ": error: "
        if let errorRange = line.range(of: ": error: ") {
            let location = Self.sourceLocation(in: line[..<errorRange.lowerBound])
            return BuildError(
                file: location.file,
                line: location.line,
                message: String(line[errorRange.upperBound...]),
                column: location.column,
            )
        }

        // Fatal error with message
        if let fatalRange = line.range(of: ": Fatal error: ") {
            let location = Self.sourceLocation(in: line[..<fatalRange.lowerBound])
            return BuildError(
                file: location.file,
                line: location.line,
                message: String(line[fatalRange.upperBound...]),
                column: location.column,
            )
        }

        // Fatal error without trailing message. A prefix that names no line is not a location, so
        // the line falls through to the markers below rather than reporting a bare path.
        if line.hasSuffix(": Fatal error"), !line.contains(" xctest[") {
            let location = Self.sourceLocation(in: line.dropLast(": Fatal error".count))

            if let lineNumber = location.line {
                return BuildError(
                    file: location.file,
                    line: lineNumber,
                    message: "Fatal error",
                    column: location.column,
                )
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

        return line.contains("Command PhaseScriptExecution failed with a nonzero exit")
            ? BuildError(file: nil, line: nil, message: line)
            : nil
    }

    private func parseWarning(_ line: String) -> BuildWarning? {
        if isJSONLikeLine(line) { return nil }

        if line.hasPrefix(" "), line.contains("|") || line.contains("`") { return nil }

        if let warningRange = line.range(of: ": warning: ") {
            let location = Self.sourceLocation(in: line[..<warningRange.lowerBound])
            return BuildWarning(
                file: location.file,
                line: location.line,
                message: String(line[warningRange.upperBound...]),
                column: location.column,
            )
        }

        if line.hasPrefix("warning: ") {
            let message = String(line.dropFirst(9))
            return BuildWarning(file: nil, line: nil, message: message)
        }

        return nil
    }

    // MARK: - Runtime Warning Parsing

    private func parseRuntimeWarning(_ line: String) -> BuildWarning? {
        if line.contains(": warning:") || line.contains(": error:") { return nil }

        guard line.hasPrefix("/"), line.contains(".swift:") else { return nil }

        if line.contains("|") || line.contains("`-") { return nil }

        guard let swiftColonRange = line.range(of: ".swift:") else { return nil }

        let afterColon = line[swiftColonRange.upperBound...]

        var lineNumEnd = afterColon.startIndex

        while lineNumEnd < afterColon.endIndex, afterColon[lineNumEnd].isNumber {
            lineNumEnd = afterColon.index(after: lineNumEnd)
        }

        guard lineNumEnd > afterColon.startIndex,
              lineNumEnd < afterColon.endIndex,
              afterColon[lineNumEnd] == " " else { return nil }

        let lineNumStr = String(afterColon[..<lineNumEnd])
        guard let lineNum = Int(lineNumStr) else { return nil }

        let file = Self.trimmedPath(line[..<swiftColonRange.lowerBound]) + ".swift"
        let message = String(afterColon[afterColon.index(after: lineNumEnd)...])

        guard !message.isEmpty else { return nil }

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

        return swiftuiKeywords.contains(where: { message.contains($0) })
            ? .swiftui
            : .runtime
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
               let secondsEnd = line.range(of: " seconds", options: .backwards) {
                duration = Self.parseSeconds(line[lastParen.upperBound..<secondsEnd.lowerBound])
            }

            recordPassedTest(named: testName, duration: duration)
            return true
        }

        // Swift Testing: <symbol> Test "name" passed or <symbol> Test funcName() passed
        if let testRange = line.range(of: "Test ") {
            let afterTest = line[testRange.upperBound...]
            // Skip "Test run with" (summary line) and "Test Case" (XCTest format)
            guard !afterTest.hasPrefix("run with "), !afterTest.hasPrefix("Case ")
            else { return false }
            let nameStart = testRange.upperBound

            if let extracted = extractSwiftTestingName(from: line, after: nameStart) {
                let remaining = line[extracted.endIndex...]

                if remaining.hasPrefix(" passed") {
                    var duration: Double?

                    if let afterRange = remaining.range(of: " after ") {
                        let afterStr = remaining[afterRange.upperBound...]

                        if let secondsRange = afterStr.range(of: " seconds") {
                            duration = Self.parseSeconds(afterStr[..<secondsRange.lowerBound])
                        }
                    }
                    recordPassedTest(named: extracted.name, duration: duration)
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Performance Measurement Parsing

    /// Parses XCTest measure() output lines.
    ///
    /// Format:
    /// `measured [Time, seconds] average: 0.037, relative standard deviation: 112.254%, values: [0.125, 0.033, ...]`
    /// May also have a leading path/test prefix or whitespace.
    private func parsePerformanceMeasurement(_ line: String) {
        guard let metricStart = line.range(of: "measured [") else { return }
        let afterMeasured = line[metricStart.upperBound...]

        // Extract metric name: everything up to the closing "]"
        guard let metricEnd = afterMeasured.firstIndex(of: "]") else { return }
        let metric = String(afterMeasured[..<metricEnd])

        let rest = afterMeasured[afterMeasured.index(after: metricEnd)...]

        // Extract average
        guard let avgRange = rest.range(of: "average: ") else { return }
        let afterAvg = rest[avgRange.upperBound...]
        guard let avgComma = afterAvg.firstIndex(of: ",") else { return }
        guard let average = Double(afterAvg[..<avgComma]) else { return }

        // Extract relative standard deviation
        guard let rsdRange = rest.range(of: "relative standard deviation: ") else { return }
        let afterRsd = rest[rsdRange.upperBound...]
        guard let pctIndex = afterRsd.firstIndex(of: "%") else { return }
        guard let rsd = Double(afterRsd[..<pctIndex]) else { return }

        // Extract values array
        var values: [Double] = []

        if let valuesRange = rest.range(of: "values: [") {
            let afterValues = rest[valuesRange.upperBound...]

            if let closeBracket = afterValues.firstIndex(of: "]") {
                let valuesStr = afterValues[..<closeBracket]

                for part in valuesStr.split(separator: ",") {
                    if let v = Double(part.trimmingCharacters(in: .whitespaces)) {
                        values.append(v)
                    }
                }
            }
        }

        let testName = state.lastStartedTestName ?? "unknown"
        state.performanceMeasurements.append(PerformanceMeasurement(
            test: testName, metric: metric, average: average, relativeStandardDeviation: rsd,
            values: values,
        ))
    }

    private func parseFailedTest(_ line: String) -> FailedTest? {
        // XCUnit test failures
        if line.contains("XCTAssertEqual failed") || line.contains("XCTAssertTrue failed")
            || line.contains("XCTAssertFalse failed")
        {
            if let errorRange = line.range(of: ": error: -["),
               let bracketEnd = line.range(of: "] : ", range: errorRange.upperBound..<line.endIndex)
            {
                let testName = String(line[errorRange.upperBound..<bracketEnd.lowerBound])
                let message = String(line[bracketEnd.upperBound...])
                let location = Self.sourceLocation(in: line[..<errorRange.lowerBound])

                if let lineNumber = location.line {
                    return FailedTest(
                        test: testName, message: message, file: location.file, line: lineNumber,
                    )
                }
            }

            if let bracketStart = line.range(of: "-["),
               let bracketEnd = line.range(of: "]", range: bracketStart.upperBound..<line.endIndex)
            {
                let testName = String(line[bracketStart.upperBound..<bracketEnd.lowerBound])
                return FailedTest(
                    test: testName,
                    message: line.trimmingCharacters(in: .whitespaces),
                    file: nil, line: nil,
                )
            }

            return FailedTest(
                test: "Test assertion",
                message: line.trimmingCharacters(in: .whitespaces),
                file: nil, line: nil,
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
               let secondsEnd = line.range(of: " seconds", options: .backwards) {
                duration = Self.parseSeconds(line[lastParen.upperBound..<secondsEnd.lowerBound])
            }

            let normalizedTest = normalizeTestName(test)
            if let dur = duration { state.failedTestDurations[normalizedTest] = dur }

            let message = duration.map { String(format: "%.3f seconds", $0) } ?? "failed"
            return FailedTest(
                test: test, message: message, file: nil, line: nil, duration: duration,
            )
        }

        // Swift Testing: <symbol> Test "name" recorded an issue at file:line:column: message Also
        // supports unquoted: <symbol> Test funcName() recorded an issue at ... Also handles
        // parameterized: Test "name" recorded an issue with N argument value(s) → ... at
        // file:line:col: message Also handles no-location: Test "name" recorded an issue: message
        if let testRange = line.range(of: "Test ") {
            let afterTest = line[testRange.upperBound...]
            // Skip "Test run with" (summary line) and "Test Case" (XCTest format)
            guard !afterTest.hasPrefix("run with "), !afterTest.hasPrefix("Case ")
            else { return nil }
            guard let extracted = extractSwiftTestingName(from: line, after: testRange.upperBound)
            else { return nil }
            let remaining = line[extracted.endIndex...]

            // the run summary counts issues, so the names are what give a count of failing tests
            func recordingFailure(_ failure: FailedTest) -> FailedTest {
                state.swiftTestingFailedTestNames.insert(normalizeTestName(failure.test))
                return failure
            }

            let issuePrefix = " recorded an issue"

            if remaining.hasPrefix(issuePrefix) {
                let afterIssueMarker = remaining[
                    remaining.index(remaining.startIndex, offsetBy: issuePrefix.count)...,
                ]

                // " at " follows directly or after "with N argument value(s) → ..."
                if let atRange = afterIssueMarker.range(of: " at ") {
                    let afterAt = String(afterIssueMarker[atRange.upperBound...])
                    let parts = afterAt.split(
                        separator: ":", maxSplits: 3, omittingEmptySubsequences: false,
                    )

                    if parts.count >= 4, let lineNum = Int(parts[1]) {
                        let file = String(parts[0])
                        let message = String(parts[3]).trimmingCharacters(in: .whitespaces)

                        // Preserve argument values from parameterized tests (→ value)
                        var testName = extracted.name
                        let beforeAt = afterIssueMarker[..<atRange.lowerBound]

                        if let arrowRange = beforeAt.range(of: " → ") {
                            let argDesc = String(beforeAt[arrowRange.upperBound...])
                                .trimmingCharacters(in: .whitespaces)
                            if !argDesc.isEmpty { testName = "\(extracted.name) (→ \(argDesc))" }
                        }

                        return recordingFailure(FailedTest(
                            test: testName, message: message, file: file, line: lineNum,
                        ))
                    }
                }

                // No-location variant: " recorded an issue: message"
                if afterIssueMarker.hasPrefix(": ") {
                    let message = String(afterIssueMarker.dropFirst(2))
                    return recordingFailure(FailedTest(
                        test: extracted.name, message: message, file: nil, line: nil))
                }
            }

            let failedMarker = " failed after "

            if remaining.hasPrefix(failedMarker) {
                let afterStr = remaining[
                    remaining.index(remaining.startIndex, offsetBy: failedMarker.count)...,
                ]
                var duration: Double?

                if let secondsRange = afterStr.range(of: " seconds") {
                    duration = Self.parseSeconds(afterStr[..<secondsRange.lowerBound])
                }

                let normalizedTest = normalizeTestName(extracted.name)
                if let dur = duration { state.failedTestDurations[normalizedTest] = dur }

                return recordingFailure(FailedTest(
                    test: extracted.name, message: "Test failed", file: nil, line: nil,
                    duration: duration,
                ))
            }
        }

        // ❌ testname (message)
        if line.hasPrefix("❌ "),
           let parenStart = line.range(of: " ("),
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

    // MARK: - Terminal Markers

    /// The outcome an xcodebuild terminal marker reports.
    private enum TerminalOutcome { case succeeded, failed }

    /// A terminal marker split into the phase it closes and the outcome it reports.
    private struct TerminalMarker {
        let phase: String
        let outcome: TerminalOutcome
    }

    /// The xcodebuild actions that end with a terminal marker, in the title case xcbeautify prints.
    ///
    /// `Test Execute` comes before `Test` so the longer phase name wins the match.
    private static let terminalPhaseNames = [
        "Build", "Test Execute", "Test", "Archive", "Export", "Analyze", "Install", "Clean",
    ]

    /// Every unfenced marker xcbeautify prints, paired with the marker it reports.
    ///
    /// The table is built once. ``parseUnfencedTerminalMarker(_:)`` runs on every line that carries
    /// `Succeeded` or `Failed`, so building the needles per call would allocate a string per phase
    /// on the parse hot path.
    private static let unfencedTerminalMarkers: [(needle: String, marker: TerminalMarker)] =
        terminalPhaseNames.flatMap { phase in
            let name = phase.uppercased()
            return [
                (
                    needle: "\(phase) Succeeded",
                    marker: TerminalMarker(phase: name, outcome: .succeeded)
                ),
                (
                    needle: "\(phase) Failed",
                    marker: TerminalMarker(phase: name, outcome: .failed)
                ),
            ]
        }

    /// Reads a fenced terminal marker of the shape `** <PHASE> SUCCEEDED **` or
    /// `** <PHASE> FAILED **`.
    ///
    /// xcodebuild closes every action with this shape. Matching the shape covers `ARCHIVE`,
    /// `EXPORT`, `ANALYZE`, `INSTALL`, and `CLEAN` without one literal per phase. The phase must be
    /// uppercase, which keeps prose that holds the same fences out of the match.
    private static func parseFencedTerminalMarker(_ line: String) -> TerminalMarker? {
        guard let open = line.range(of: "** "),
              let close = line.range(of: " **", range: open.upperBound..<line.endIndex)
        else { return nil }

        let body = line[open.upperBound..<close.lowerBound]

        let outcome: TerminalOutcome
        let phase: Substring

        if body.hasSuffix(" SUCCEEDED") {
            outcome = .succeeded
            phase = body.dropLast(" SUCCEEDED".count)
        } else if body.hasSuffix(" FAILED") {
            outcome = .failed
            phase = body.dropLast(" FAILED".count)
        } else {
            return nil
        }

        guard !phase.isEmpty, phase.allSatisfy({ $0.isUppercase || $0 == " " }) else { return nil }

        return TerminalMarker(phase: String(phase), outcome: outcome)
    }

    /// Reads an unfenced terminal marker such as `Archive Succeeded` or `Test Failed`.
    ///
    /// xcbeautify rewrites the xcodebuild marker in title case and drops the `**` fences. The phase
    /// must come from ``unfencedTerminalMarkers``, because an unfenced marker has no shape that
    /// separates it from ordinary output.
    private static func parseUnfencedTerminalMarker(_ line: String) -> TerminalMarker? {
        // Two scans reject the ordinary line, instead of one scan per entry in the table.
        guard line.contains("Succeeded") || line.contains("Failed") else { return nil }

        return unfencedTerminalMarkers.first { line.contains($0.needle) }?.marker
    }

    /// Records the outcome a terminal marker reports.
    ///
    /// Both marker shapes carry the same meaning, so both call this method.
    private func record(_ marker: TerminalMarker) {
        switch marker.outcome {
            case .succeeded: state.sawTerminalSuccessMarker = true
            case .failed:
                state.sawTerminalFailureMarker = true
                // A failed test action stands in for the individual failure lines a crashed run
                // never printed. `TEST` and `TEST EXECUTE` both carry that meaning.
                if marker.phase.hasPrefix("TEST") { state.testRunFailed = true }
        }
    }

    private func parseBuildAndTestTime(_ line: String) {
        if let marker = Self.parseFencedTerminalMarker(line) {
            record(marker)

            // Some xcodebuild versions append the elapsed time in brackets to the marker.
            if let bracketStart = line.range(of: "[", options: .backwards),
               let bracketEnd = line.range(of: "]", options: .backwards),
               bracketStart.lowerBound < bracketEnd.lowerBound {
                state.buildTime = String(line[bracketStart.upperBound..<bracketEnd.lowerBound])
            }
            return
        }

        if line.hasPrefix("Build complete!") {
            state.sawTerminalSuccessMarker = true

            if let parenStart = line.range(of: "("),
               let parenEnd = line.range(of: ")"),
               parenStart.lowerBound < parenEnd.lowerBound {
                state.buildTime = String(line[parenStart.upperBound..<parenEnd.lowerBound])
            }
            return
        }

        // Terminal success forms: "Build succeeded in 1.2s" (swift build), "Build succeeded
        // (2.3s)", and xcbeautify's capitalized "Build Succeeded".
        if line.hasPrefix("Build succeeded") || line.hasPrefix("Build Succeeded") {
            state.sawTerminalSuccessMarker = true

            if line.hasPrefix("Build succeeded in ") {
                state.buildTime = String(line.dropFirst("Build succeeded in ".count))
            } else if let parenStart = line.range(of: "("),
               let parenEnd = line.range(of: ")", options: .backwards),
               parenStart.lowerBound < parenEnd.lowerBound {
                state.buildTime = String(line[parenStart.upperBound..<parenEnd.lowerBound])
            }
            return
        }

        // Terminal failure forms: "Build failed after 1.2s", "Build failed (2 errors, …)", and
        // xcbeautify's capitalized "Build Failed".
        if line.hasPrefix("Build failed") || line.hasPrefix("Build Failed") {
            state.sawTerminalFailureMarker = true

            if line.hasPrefix("Build failed after ") {
                state.buildTime = String(line.dropFirst("Build failed after ".count))
            }
            return
        }

        // xcbeautify rewrites the terminal markers without the `** **` fences, for every phase.
        if let marker = Self.parseUnfencedTerminalMarker(line) {
            record(marker)
            return
        }

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // XCTest: Executed N tests, with N failures
        if trimmedLine.hasPrefix("Executed "), let withRange = trimmedLine.range(of: ", with ") {
            let afterExecuted = trimmedLine[
                trimmedLine.index(trimmedLine.startIndex, offsetBy: 9)..<withRange.lowerBound,
            ]
            let testCountStr = afterExecuted.split(separator: " ").first
            let total = testCountStr.flatMap { Int($0) } ?? 0

            let afterWith = String(trimmedLine[withRange.upperBound...])
            var failures = 0

            if let failureRange = afterWith.range(of: " failure") {
                let beforeFailure = afterWith[..<failureRange.lowerBound]
                let words = beforeFailure.split(separator: " ")
                if let lastWord = words.last, let parsed = Int(lastWord) { failures = parsed }
            }

            var time: Double = 0

            if let inRange = trimmedLine.range(
                of: " in ", range: withRange.upperBound..<trimmedLine.endIndex,
            ) {
                let afterIn = trimmedLine[inRange.upperBound...]

                if let parenStart = afterIn.range(of: " (") {
                    time = Self.parseTestTime(String(afterIn[..<parenStart.lowerBound])) ?? 0
                } else if let secondsRange = afterIn.range(of: " seconds", options: .backwards) {
                    time = Self.parseTestTime(String(afterIn[..<secondsRange.lowerBound])) ?? 0
                }
            }

            recordXCTestTally(executed: total, failed: failures, time: time)
            state.currentSuiteName = nil
            return
        }

        // Swift Testing failure summary (two formats): Format 1: Test run with N tests failed, M
        // tests passed after X seconds. Format 2: Test run with N test(s) in M suite(s) failed
        // after X seconds with Y issue(s).
        if let testRunRange = line.range(of: "Test run with ") {
            // Format 1: "N tests failed, M tests passed after X seconds."
            if let failedRange = line.range(
                of: " failed, ", range: testRunRange.upperBound..<line.endIndex,
            ),
               let passedRange = line.range(
                   of: " passed after ", range: failedRange.upperBound..<line.endIndex,
               )
            {
                let beforeFailed = line[testRunRange.upperBound..<failedRange.lowerBound]
                let failedCountStr = beforeFailed.split(separator: " ").first

                if let failedCountStr, let failedCount = Int(failedCountStr) {
                    state.swiftTestingFailedCount =
                        (state.swiftTestingFailedCount ?? 0) + failedCount

                    let beforePassed = line[failedRange.upperBound..<passedRange.lowerBound]
                    let passedCountStr = beforePassed.split(separator: " ").first

                    if let passedCountStr, let passedCount = Int(passedCountStr) {
                        state.swiftTestingExecutedCount =
                            (state.swiftTestingExecutedCount ?? 0) + passedCount + failedCount
                    }
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
                of: " failed after ", range: testRunRange.upperBound..<line.endIndex,
            ),
               line.contains(" issue")
            {
                let beforeFailed = line[testRunRange.upperBound..<failedAfterRange.lowerBound]
                let testCountStr = beforeFailed.split(separator: " ").first

                if let testCountStr, let total = Int(testCountStr) {
                    state.swiftTestingExecutedCount = (state.swiftTestingExecutedCount ?? 0) + total

                    let afterFailed = line[failedAfterRange.upperBound...]
                    let issues = Self.parseIssueCounts(inSummarySuffix: afterFailed)
                    state.swiftTestingKnownIssueCount += issues.known
                    // A summary that names no count at all leaves every test suspect. A line that
                    // says failed carries at least one failure, whatever its counts parse to, so
                    // the run never reads as a pass on a wording the scan does not know.
                    let failed = issues.isEmpty ? total : max(issues.errors, 1)
                    state.swiftTestingFailedCount = (state.swiftTestingFailedCount ?? 0) + failed

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
                    state.swiftTestingExecutedCount = (state.swiftTestingExecutedCount ?? 0) + total

                    // A run that records a known issue still passes, and the summary says so.
                    state.swiftTestingKnownIssueCount += Self
                        .parseIssueCounts(inSummarySuffix: line[passedAfter.upperBound...]).known

                    if total > 0 {
                        let afterPassed = line[passedAfter.upperBound...]

                        if let secondsRange = afterPassed.range(of: " seconds", options: .backwards)
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
        if let time = Self.parseTestTime(timeString) { state.testTimeAccumulator += time }
    }

    private static func parseTestTime(_ timeString: String) -> Double? {
        parseSeconds(timeString.trimmingCharacters(in: CharacterSet(charactersIn: ".\t")))
    }

    /// The issue counts a Swift Testing run summary carries
    ///
    /// Swift Testing puts a warning and a known issue in the same total as a failed expectation, so
    /// the total alone overstates how many tests broke.
    private struct IssueCounts {
        var total = 0
        var warnings = 0
        var known = 0

        /// The issues that failed a test
        ///
        /// A summary that names no total reports a warning or a known issue alone, and the run
        /// passed, so the difference is zero.
        var errors: Int { max(total - warnings - known, 0) }

        var isEmpty: Bool { total == 0 && warnings == 0 && known == 0 }
    }

    /// Reads the issue counts out of the tail of a Swift Testing run summary.
    ///
    /// The tail takes eight shapes, from ` with 3 issues` to
    /// ` with 10 issues (including 2 warnings and 3 known issues)`, so the scan reads every
    /// number-and-noun pair rather than matching each shape.
    ///
    /// - Parameter suffix: Everything after `failed after` or `passed after` on the summary line.
    /// - Returns: Zeroed counts when the line names no issue.
    private static func parseIssueCounts(
        inSummarySuffix suffix: some StringProtocol
    ) -> IssueCounts {
        var counts = IssueCounts()
        guard let withRange = suffix.range(of: " with ") else { return counts }

        let punctuation = CharacterSet(charactersIn: "(),.")
        let tokens = suffix[withRange.upperBound...].split(separator: " ")

        for (index, token) in tokens.enumerated() where index + 1 < tokens.count {
            guard let value = Int(token.trimmingCharacters(in: punctuation)) else { continue }
            let noun = tokens[index + 1].trimmingCharacters(in: punctuation)

            if noun.hasPrefix("known") {
                counts.known += value
            } else if noun.hasPrefix("warning") {
                counts.warnings += value
            } else if noun.hasPrefix("issue") { counts.total += value }
        }

        return counts
    }

    /// Files one `Executed N tests` line under the suite level that produced it.
    ///
    /// A `.xctest` line adds to the bundle total, because two bundles hold disjoint tests. Any
    /// other level replaces the fallback only when it reports more tests, because the levels above
    /// a bundle repeat the tests the bundle already counted. The failure count and the duration
    /// travel with the line that wins, so all three describe the same suite level.
    private func recordXCTestTally(executed: Int, failed: Int, time: Double) {
        if state.currentSuiteName?.hasSuffix(".xctest") == true {
            state.xctestBundleTally.executed += executed
            state.xctestBundleTally.failed += failed
            state.xctestBundleTally.time += time
            state.xctestBundleTally.seen = true
            return
        }

        guard !state.xctestOuterTally.seen || executed > state.xctestOuterTally.executed else {
            return
        }

        state.xctestOuterTally = XCTestTally(
            executed: executed, failed: failed, time: time, seen: true)
    }

    // MARK: - Build Phase Parsing

    private func addPhaseToTarget(_ phase: String, target: String) {
        if state.targetPhases[target] == nil {
            state.targetPhases[target] = []
            if state.targetOrderSet.insert(target).inserted { state.targetOrder.append(target) }
        }
        if state.targetPhaseSet[target, default: []].insert(phase).inserted {
            state.targetPhases[target, default: []].append(phase)
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

        if line.contains("SwiftDriver"),
           line.contains("Compilation"),
           let target = extractTarget(from: line) { return ("SwiftCompilation", target) }

        return nil
    }

    private func parseSPMPhase(_ line: String) -> (String, String)? {
        if line.contains("] Compiling ") {
            if let compilingRange = line.range(of: "] Compiling ") {
                let afterCompiling = line[compilingRange.upperBound...]
                let parts = afterCompiling.split(separator: " ", maxSplits: 1)

                if let targetName = parts.first {
                    let target = String(targetName)
                    return target == "plugin"
                        ? nil
                        : ("Compiling", target)
                }
            }
        }

        if line.contains("] Linking ") {
            if let linkingRange = line.range(of: "] Linking ") {
                let afterLinking = line[linkingRange.upperBound...]
                let targetName = afterLinking.trimmingCharacters(in: .whitespaces)
                if !targetName.isEmpty { return ("Linking", targetName) }
            }
        }

        return nil
    }

    // MARK: - Dependency Graph Parsing

    private func parseDependencyGraph(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("Target '"), trimmed.contains("' in project '") {
            let afterTarget = trimmed.dropFirst("Target '".count)

            if let endQuote = afterTarget.range(of: "'") {
                let targetName = String(afterTarget[..<endQuote.lowerBound])
                state.currentDependencyTarget = targetName

                if state.targetOrderSet.insert(targetName).inserted {
                    state.targetOrder.append(targetName)
                }

                if trimmed.hasSuffix("(no dependencies)") {
                    state.targetDependencies[targetName] = []
                    state.targetDependencySet[targetName] = []
                }
                return true
            }
        }

        if trimmed.contains("dependency on target '"),
           let currentTarget = state.currentDependencyTarget
        {
            if let startQuote = trimmed.range(of: "dependency on target '") {
                let afterStartQuote = trimmed[startQuote.upperBound...]

                if let endQuote = afterStartQuote.range(of: "'") {
                    let dependencyName = String(afterStartQuote[..<endQuote.lowerBound])

                    if state.targetDependencySet[currentTarget, default: []].insert(dependencyName)
                        .inserted
                    {
                        state.targetDependencies[currentTarget, default: []].append(dependencyName)
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
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        let afterPrefix = line.dropFirst(prefix.count)

        guard let targetRange = afterPrefix.range(of: " (in target '") else { return nil }

        let path = String(afterPrefix[..<targetRange.lowerBound])

        if !path.hasSuffix(".app") { return nil }

        let name = URL(fileURLWithPath: path).lastPathComponent

        let afterTarget = afterPrefix[targetRange.upperBound...]
        guard let targetEnd = afterTarget.range(of: "' from project") else { return nil }

        let target = String(afterTarget[..<targetEnd.lowerBound])

        return Executable(path: path, name: name, target: target)
    }
}
