import Foundation

/// Parses `.xcresult` bundles using `xcresulttool` for detailed test results.
///
/// Extracts complete failure messages and test output that may be truncated
/// in xcodebuild's text output.
public enum XCResultParser {
    /// Detailed test results extracted from an xcresult bundle.
    public struct TestResults: Sendable {
        /// Failed tests with complete failure messages.
        public let failures: [FailedTest]
        /// Total number of passed tests.
        public let passedCount: Int
        /// Total number of failed tests.
        public let failedCount: Int
        /// Total test duration in seconds.
        public let duration: Double?
        /// Test output (stdout) captured from test processes.
        public let testOutput: String?
    }

    /// Extracts test results from an xcresult bundle.
    ///
    /// - Parameter path: Path to the `.xcresult` bundle.
    /// - Returns: Parsed test results, or nil if parsing fails.
    public static func parseTestResults(at path: String) -> TestResults? {
        guard let json = runXCResultTool(path: path) else { return nil }
        return parseTestJSON(json)
    }

    // MARK: - Private

    private static func runXCResultTool(path: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xcresulttool", "get", "test-results", "tests", "--path", path, "--compact",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            // Read pipe data before waitUntilExit() to avoid deadlock when
            // output exceeds the OS pipe buffer (~64KB).
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            guard !data.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return json
        } catch {
            return nil
        }
    }

    private static func parseTestJSON(_ json: [String: Any]) -> TestResults {
        var failures: [FailedTest] = []
        var passedCount = 0
        var failedCount = 0
        var totalDuration: Double?

        guard let testNodes = json["testNodes"] as? [[String: Any]] else {
            return TestResults(
                failures: [], passedCount: 0, failedCount: 0,
                duration: nil, testOutput: nil,
            )
        }

        // Collect duration from the top-level test plan node
        for node in testNodes {
            if let dur = node["durationInSeconds"] as? Double {
                totalDuration = (totalDuration ?? 0) + dur
            }
        }

        // Walk the tree to find test cases
        collectTestCases(
            from: testNodes,
            failures: &failures,
            passedCount: &passedCount,
            failedCount: &failedCount,
        )

        // Collect test output from attachment nodes
        let testOutput = collectTestOutput(from: testNodes)

        return TestResults(
            failures: failures,
            passedCount: passedCount,
            failedCount: failedCount,
            duration: totalDuration,
            testOutput: testOutput,
        )
    }

    private static func collectTestCases(
        from nodes: [[String: Any]],
        failures: inout [FailedTest],
        passedCount: inout Int,
        failedCount: inout Int,
    ) {
        for node in nodes {
            let nodeType = node["nodeType"] as? String ?? ""
            let result = node["result"] as? String

            if nodeType == "Test Case" {
                if result == "Passed" {
                    passedCount += 1
                } else if result == "Failed" {
                    failedCount += 1
                    if let failure = extractFailure(from: node) {
                        failures.append(failure)
                    }
                }
            }

            // Recurse into children
            if let children = node["children"] as? [[String: Any]] {
                collectTestCases(
                    from: children,
                    failures: &failures,
                    passedCount: &passedCount,
                    failedCount: &failedCount,
                )
            }
        }
    }

    private static func extractFailure(from testCase: [String: Any]) -> FailedTest? {
        let testName = testCase["name"] as? String ?? "Unknown test"
        let duration = testCase["durationInSeconds"] as? Double

        guard let children = testCase["children"] as? [[String: Any]] else {
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
        from nodes: [[String: Any]],
        messages: inout [String],
        file: inout String?,
        line: inout Int?,
    ) {
        for node in nodes {
            let nodeType = node["nodeType"] as? String ?? ""

            if nodeType == "Failure Message" {
                if let name = node["name"] as? String, !name.isEmpty {
                    messages.append(name)
                }
            } else if nodeType == "Source Code Reference" {
                if let name = node["name"] as? String {
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

            // Recurse
            if let children = node["children"] as? [[String: Any]] {
                collectFailureDetails(
                    from: children,
                    messages: &messages,
                    file: &file,
                    line: &line,
                )
            }
        }
    }

    private static func collectTestOutput(from nodes: [[String: Any]]) -> String? {
        var outputs: [String] = []
        collectOutputNodes(from: nodes, outputs: &outputs)
        return outputs.isEmpty ? nil : outputs.joined(separator: "\n")
    }

    private static func collectOutputNodes(
        from nodes: [[String: Any]],
        outputs: inout [String],
    ) {
        for node in nodes {
            let nodeType = node["nodeType"] as? String ?? ""

            // Attachments with "Standard Output" or similar names contain test stdout
            if nodeType == "Attachment" {
                if let name = node["name"] as? String,
                   name.localizedCaseInsensitiveContains("output")
                {
                    if let details = node["details"] as? String, !details.isEmpty {
                        outputs.append(details)
                    }
                }
            }

            if let children = node["children"] as? [[String: Any]] {
                collectOutputNodes(from: children, outputs: &outputs)
            }
        }
    }
}
