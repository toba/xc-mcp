import Testing

@testable import XCMCPCore

@Suite("BuildResultFormatter Tests")
struct BuildResultFormatterTests {
    @Test("Format successful build")
    func testFormatSuccessfulBuild() {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: nil, buildTime: "2.3s"
            ),
            errors: [],
            warnings: [],
            failedTests: []
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        #expect(formatted.contains("Build succeeded"))
        #expect(formatted.contains("2.3s"))
    }

    @Test("Format failed build with errors")
    func testFormatFailedBuild() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 2, warnings: 1, failedTests: 0, passedTests: nil, buildTime: "5.1s"
            ),
            errors: [
                BuildError(
                    file: "Foo.swift", line: 42, message: "cannot convert 'Int' to 'String'",
                    column: 10),
                BuildError(file: "Bar.swift", line: 15, message: "missing return", column: 5),
            ],
            warnings: [
                BuildWarning(file: "Baz.swift", line: 88, message: "unused variable 'x'", column: 3)
            ],
            failedTests: []
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        #expect(formatted.contains("Build failed"))
        #expect(formatted.contains("2 errors"))
        #expect(formatted.contains("1 warning"))
        #expect(formatted.contains("Foo.swift:42:10"))
        #expect(formatted.contains("cannot convert"))
        #expect(formatted.contains("Baz.swift:88:3"))
    }

    @Test("Format test results passed")
    func testFormatTestResultsPassed() {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: 42, buildTime: nil,
                testTime: "3.2s"
            ),
            errors: [],
            warnings: [],
            failedTests: []
        )

        let formatted = BuildResultFormatter.formatTestResult(result)
        #expect(formatted.contains("Tests passed"))
        #expect(formatted.contains("42 passed"))
        #expect(formatted.contains("3.2s"))
    }

    @Test("Format test results with failures")
    func testFormatTestResultsFailed() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 2, passedTests: 40, buildTime: nil,
                testTime: "3.2s"
            ),
            errors: [],
            warnings: [],
            failedTests: [
                FailedTest(
                    test: "MyTests.testLogin", message: "Expected true, got false",
                    file: "MyTests.swift", line: 55),
                FailedTest(
                    test: "MyTests.testLogout", message: "Timeout after 5.0s", file: nil, line: nil),
            ]
        )

        let formatted = BuildResultFormatter.formatTestResult(result)
        #expect(formatted.contains("Tests failed"))
        #expect(formatted.contains("2 failed"))
        #expect(formatted.contains("40 passed"))
        #expect(formatted.contains("MyTests.testLogin"))
        #expect(formatted.contains("Expected true, got false"))
        #expect(formatted.contains("MyTests.swift:55"))
        #expect(formatted.contains("Timeout after 5.0s"))
    }

    @Test("Format linker errors")
    func testFormatLinkerErrors() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, linkerErrors: 1, passedTests: nil,
                buildTime: nil
            ),
            errors: [],
            warnings: [],
            failedTests: [],
            linkerErrors: [
                LinkerError(symbol: "_MissingFunc", architecture: "arm64", referencedFrom: "main.o")
            ]
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        #expect(formatted.contains("Linker errors:"))
        #expect(formatted.contains("_MissingFunc"))
        #expect(formatted.contains("arm64"))
    }

    @Test("Format coverage in test results")
    func testFormatCoverageInTestResults() {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: 10, buildTime: nil,
                coveragePercent: 75.5
            ),
            errors: [],
            warnings: [],
            failedTests: [],
            coverage: CodeCoverage(lineCoverage: 75.5, files: [])
        )

        let formatted = BuildResultFormatter.formatTestResult(result)
        #expect(formatted.contains("Coverage: 75.5%"))
    }

    @Test("ErrorExtractor.extractBuildErrors integration")
    func testErrorExtractorIntegration() {
        let output = """
            Building for debugging...
            main.swift:10:5: error: cannot find 'x' in scope
            main.swift:20:3: warning: unused variable 'y'
            Build failed after 1.2 seconds
            """

        let formatted = ErrorExtractor.extractBuildErrors(from: output)
        #expect(formatted.contains("Build failed"))
        #expect(formatted.contains("1 error"))
        #expect(formatted.contains("main.swift:10:5"))
    }

    @Test("ErrorExtractor.extractTestResults integration")
    func testErrorExtractorTestResultsIntegration() {
        let output = """
            Test Case 'MyTests.testA' passed (0.001 seconds).
            Test Case 'MyTests.testB' passed (0.002 seconds).
            Executed 2 tests, with 0 failures (0 unexpected) in 0.003 (0.005) seconds
            """

        let formatted = ErrorExtractor.extractTestResults(from: output)
        #expect(formatted.contains("Tests passed"))
        #expect(formatted.contains("2 passed"))
    }
}
