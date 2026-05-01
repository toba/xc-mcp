import Foundation
import Subprocess

/// Parses `.xcresult` bundles using `xcresulttool` for detailed test results.
///
/// Extracts complete failure messages and test output that may be truncated
/// in xcodebuild's text output.
public enum XCResultParser {
    /// Status of an individual test case.
    public enum TestStatus: String, Sendable {
        case passed = "Passed"
        case failed = "Failed"
        case skipped = "Skipped"
        case expectedFailure = "Expected Failure"
    }

    /// A performance metric from a `measure()` block.
    public struct TestPerformanceMetric: Sendable {
        public let name: String
        public let average: Double
        public let standardDeviation: Double
        public let unit: String
        public let iterations: Int
    }

    /// Detail for a single test case.
    public struct TestDetail: Sendable {
        public let name: String
        public let status: TestStatus
        public let duration: Double?
        public let skipReason: String?
        public let failureMessage: String?
        public let performanceMetrics: [TestPerformanceMetric]
    }

    /// Detailed test results extracted from an xcresult bundle.
    public struct TestResults: Sendable {
        /// Failed tests with complete failure messages.
        public let failures: [FailedTest]
        /// Total number of passed tests.
        public let passedCount: Int
        /// Total number of failed tests.
        public let failedCount: Int
        /// Total number of skipped tests.
        public let skippedCount: Int
        /// Per-test details (passed, failed, skipped with reasons, performance metrics).
        public let tests: [TestDetail]
        /// Total test duration in seconds.
        public let duration: Double?
        /// Test output (stdout) captured from test processes.
        public let testOutput: String?
    }

    /// Extracts test results from an xcresult bundle.
    ///
    /// - Parameter path: Path to the `.xcresult` bundle.
    /// - Returns: Parsed test results, or nil if parsing fails.
    public static func parseTestResults(at path: String) async -> TestResults? {
        guard let json = await runXCResultTool(path: path) else { return nil }
        return parseTestJSON(json)
    }

    // MARK: - Performance Metrics

    /// A performance metric result parsed from `xcresulttool get test-results metrics`.
    public struct PerformanceMetricResult: Sendable, Codable {
        public let testIdentifier: String
        public let testIdentifierURL: String?
        public let testRuns: [TestRunWithMetrics]
    }

    public struct TestRunWithMetrics: Sendable, Codable {
        public let testPlanConfiguration: MetricConfiguration
        public let device: MetricDevice
        public let metrics: [PerformanceMetric]
    }

    public struct MetricConfiguration: Sendable, Codable {
        public let configurationId: String
        public let configurationName: String
    }

    public struct MetricDevice: Sendable, Codable {
        public let deviceId: String
        public let deviceName: String
    }

    public struct PerformanceMetric: Sendable, Codable {
        public let displayName: String
        public let unitOfMeasurement: String
        public let measurements: [Double]
        public let identifier: String?
        public let baselineName: String?
        public let baselineAverage: Double?
        public let maxRegression: Double?
        public let maxPercentRegression: Double?
        public let maxStandardDeviation: Double?
        public let maxPercentRelativeStandardDeviation: Double?
        public let polarity: String?
    }

    /// Parses performance metrics from an xcresult bundle.
    ///
    /// - Parameters:
    ///   - path: Path to the `.xcresult` bundle.
    ///   - testId: Optional test identifier to filter results.
    /// - Returns: Parsed performance metric results, or nil if parsing fails.
    public static func parsePerformanceMetrics(
        at path: String, testId: String? = nil,
    ) async -> [PerformanceMetricResult]? {
        var arguments = [
            "xcresulttool", "get", "test-results", "metrics",
            "--path", path, "--compact",
        ]
        if let testId {
            arguments.append(contentsOf: ["--test-id", testId])
        }

        guard
            let result = try? await ProcessResult.runSubprocess(
                .name("xcrun"),
                arguments: Arguments(arguments),
                outputLimit: 8_388_608,
            )
        else { return nil }

        let data = Data(result.stdout.utf8)
        guard result.succeeded, !data.isEmpty else { return nil }

        let decoder = JSONDecoder()
        // Try decoding as array first, then as single object
        if let array = try? decoder.decode([PerformanceMetricResult].self, from: data) {
            return array
        }
        if let single = try? decoder.decode(PerformanceMetricResult.self, from: data) {
            return [single]
        }
        return nil
    }

    // MARK: - JSON Models

    /// A node in the xcresulttool test results tree.
    private struct TestNode: Decodable {
        let name: String?
        let nodeType: String?
        let result: String?
        let durationInSeconds: Double?
        let details: String?
        let children: [TestNode]?
    }

    /// Top-level response from `xcresulttool get test-results tests`.
    private struct TestResultsJSON: Decodable {
        let testNodes: [TestNode]?
    }

    // MARK: - Private

    private static func runXCResultTool(path: String) async -> TestResultsJSON? {
        guard
            let result = try? await ProcessResult.runSubprocess(
                .name("xcrun"),
                arguments: Arguments([
                    "xcresulttool", "get", "test-results", "tests", "--path", path, "--compact",
                ]),
                outputLimit: 8_388_608,
            )
        else { return nil }

        let data = Data(result.stdout.utf8)
        guard result.succeeded, !data.isEmpty else { return nil }

        return try? JSONDecoder().decode(TestResultsJSON.self, from: data)
    }

    private static func parseTestJSON(_ json: TestResultsJSON) -> TestResults {
        var failures: [FailedTest] = []
        var passedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var tests: [TestDetail] = []
        var totalDuration: Double?

        guard let testNodes = json.testNodes else {
            return TestResults(
                failures: [], passedCount: 0, failedCount: 0,
                skippedCount: 0, tests: [], duration: nil, testOutput: nil,
            )
        }

        // Collect duration from the top-level test plan node
        for node in testNodes {
            if let dur = node.durationInSeconds {
                totalDuration = (totalDuration ?? 0) + dur
            }
        }

        // Walk the tree to find test cases
        collectTestCases(
            from: testNodes,
            failures: &failures,
            passedCount: &passedCount,
            failedCount: &failedCount,
            skippedCount: &skippedCount,
            tests: &tests,
        )

        // Collect test output from attachment nodes
        let testOutput = collectTestOutput(from: testNodes)

        return TestResults(
            failures: failures,
            passedCount: passedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            tests: tests,
            duration: totalDuration,
            testOutput: testOutput,
        )
    }

    /// Walks a tree of test nodes, calling the visitor on each node.
    private static func forEachNode(
        in nodes: [TestNode],
        body: (_ node: TestNode) -> Void,
    ) {
        for node in nodes {
            body(node)
            if let children = node.children {
                forEachNode(in: children, body: body)
            }
        }
    }

    private static func collectTestCases(
        from nodes: [TestNode],
        failures: inout [FailedTest],
        passedCount: inout Int,
        failedCount: inout Int,
        skippedCount: inout Int,
        tests: inout [TestDetail],
    ) {
        forEachNode(in: nodes) { node in
            let nodeType = node.nodeType ?? ""
            let result = node.result

            if nodeType == "Test Case" {
                let name = node.name ?? "Unknown"
                let duration = node.durationInSeconds
                let status = TestStatus(rawValue: result ?? "") ?? .failed

                switch status {
                    case .passed:
                        passedCount += 1
                        tests.append(
                            TestDetail(
                                name: name, status: .passed, duration: duration,
                                skipReason: nil, failureMessage: nil, performanceMetrics: [],
                            ),
                        )
                    case .failed:
                        failedCount += 1
                        let failure = extractFailure(from: node)
                        if let failure { failures.append(failure) }
                        tests.append(
                            TestDetail(
                                name: name, status: .failed, duration: duration,
                                skipReason: nil, failureMessage: failure?.message,
                                performanceMetrics: [],
                            ),
                        )
                    case .skipped:
                        skippedCount += 1
                        let reason = extractSkipReason(from: node)
                        tests.append(
                            TestDetail(
                                name: name, status: .skipped, duration: duration,
                                skipReason: reason, failureMessage: nil, performanceMetrics: [],
                            ),
                        )
                    case .expectedFailure:
                        passedCount += 1
                        tests.append(
                            TestDetail(
                                name: name, status: .expectedFailure, duration: duration,
                                skipReason: nil, failureMessage: nil, performanceMetrics: [],
                            ),
                        )
                }
            }
        }
    }

    private static func extractSkipReason(from node: TestNode) -> String? {
        guard let children = node.children else { return nil }
        for child in children {
            let childType = child.nodeType ?? ""
            if childType == "Failure Message" || childType == "Skip Message" {
                if let name = child.name, !name.isEmpty {
                    return name
                }
            }
            // Check nested children
            if let nested = child.children {
                for nestedChild in nested {
                    let nestedType = nestedChild.nodeType ?? ""
                    if nestedType == "Failure Message" || nestedType == "Skip Message" {
                        if let name = nestedChild.name, !name.isEmpty {
                            return name
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func extractFailure(from testCase: TestNode) -> FailedTest? {
        let testName = testCase.name ?? "Unknown test"
        let duration = testCase.durationInSeconds

        guard let children = testCase.children else {
            return FailedTest(
                test: testName, message: "Test failed", file: nil, line: nil, duration: duration,
            )
        }

        // Collect all failure messages and source references from children
        var messages: [String] = []
        var file: String?
        var line: Int?

        collectFailureDetails(
            from: children,
            messages: &messages,
            file: &file,
            line: &line,
        )

        let message = messages.isEmpty ? "Test failed" : messages.joined(separator: "; ")

        return FailedTest(
            test: testName,
            message: message,
            file: file,
            line: line,
            duration: duration,
        )
    }

    private static func collectFailureDetails(
        from nodes: [TestNode],
        messages: inout [String],
        file: inout String?,
        line: inout Int?,
    ) {
        forEachNode(in: nodes) { node in
            let nodeType = node.nodeType ?? ""

            if nodeType == "Failure Message" {
                if let name = node.name, !name.isEmpty {
                    messages.append(name)
                }
            } else if nodeType == "Source Code Reference" {
                if let name = node.name {
                    // Format: "file.swift:42"
                    let parts = name.split(separator: ":", maxSplits: 1)
                    if parts.count >= 1 {
                        file = String(parts[0])
                        if parts.count >= 2 {
                            line = Int(parts[1])
                        }
                    }
                }
            }
        }
    }

    private static func collectTestOutput(from nodes: [TestNode]) -> String? {
        var outputs: [String] = []
        collectOutputNodes(from: nodes, outputs: &outputs)
        return outputs.isEmpty ? nil : outputs.joined(separator: "\n")
    }

    private static func collectOutputNodes(
        from nodes: [TestNode],
        outputs: inout [String],
    ) {
        forEachNode(in: nodes) { node in
            let nodeType = node.nodeType ?? ""

            // Attachments with "Standard Output" or similar names contain test stdout
            if nodeType == "Attachment" {
                if let name = node.name,
                   name.localizedCaseInsensitiveContains("output")
                {
                    if let details = node.details, !details.isEmpty {
                        outputs.append(details)
                    }
                }
            }
        }
    }
}
