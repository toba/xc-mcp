import Testing
import Foundation
import TobaTesting
@testable import XCMCPCore

/// Golden-file snapshot tests for `BuildResultFormatter`.
///
/// Each test constructs a `BuildResult`, formats it, and compares the output
/// character-for-character against a fixture file in `Tests/TestData/`. To update snapshots after
/// intentional formatting changes, overwrite the fixture files and re-run.
///
/// The comparison runs through `expectNoDifference`, which prints a line diff on failure. A bare
/// `#expect(a == b)` prints both formatted reports in full and leaves the reader to spot the
/// changed line.
struct BuildResultFormatterSnapshotTests {
    private func loadSnapshot(_ name: String) throws -> String {
        try String(contentsOf: TestFixtures.url("\(name).txt"), encoding: .utf8)
    }

    @Test func `Snapshot — build success`() throws {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: nil, buildTime: "2.3s",
            ),
            errors: [],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        let expected = try loadSnapshot("snapshot-build-success")
        expectNoDifference(formatted, expected)
    }

    @Test func `Snapshot — build failed with errors and warnings`() throws {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 2, warnings: 1, failedTests: 0, passedTests: nil, buildTime: "5.1s",
            ),
            errors: [
                BuildError(
                    file: "Foo.swift", line: 42, message: "cannot convert 'Int' to 'String'",
                    column: 10,
                ),
                BuildError(file: "Bar.swift", line: 15, message: "missing return", column: 5),
            ],
            warnings: [
                BuildWarning(file: "Baz.swift", line: 88, message: "unused variable 'x'", column: 3)
            ],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        let expected = try loadSnapshot("snapshot-build-failed")
        expectNoDifference(formatted, expected)
    }

    @Test func `Snapshot — tests passed`() throws {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: 42, buildTime: nil,
                testTime: "3.2s",
            ),
            errors: [],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatTestResult(result)
        let expected = try loadSnapshot("snapshot-test-passed")
        expectNoDifference(formatted, expected)
    }

    @Test func `Snapshot — tests failed`() throws {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 2, passedTests: 40, buildTime: nil,
                testTime: "3.2s",
            ),
            errors: [],
            warnings: [],
            failedTests: [
                FailedTest(
                    test: "MyTests.testLogin", message: "Expected true, got false",
                    file: "MyTests.swift", line: 55,
                ),
                FailedTest(
                    test: "MyTests.testLogout", message: "Timeout after 5.0s",
                    file: nil, line: nil,
                ),
            ],
        )

        let formatted = BuildResultFormatter.formatTestResult(result)
        let expected = try loadSnapshot("snapshot-test-failed")
        expectNoDifference(formatted, expected)
    }

    @Test func `Snapshot — linker errors`() throws {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, linkerErrors: 1, passedTests: nil,
                buildTime: nil,
            ),
            errors: [],
            warnings: [],
            failedTests: [],
            linkerErrors: [
                LinkerError(symbol: "_MissingFunc", architecture: "arm64", referencedFrom: "main.o")
            ],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        let expected = try loadSnapshot("snapshot-linker-errors")
        expectNoDifference(formatted, expected)
    }

    @Test func `Snapshot — cascade errors from script phase`() throws {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 4, warnings: 0, failedTests: 0, passedTests: nil, buildTime: "5.0s",
            ),
            errors: [
                BuildError(
                    file: nil, line: nil,
                    message:
                        "Error: Unknown option --srcdir Command PhaseScriptExecution failed with a nonzero exit code",
                ),
                BuildError(
                    file: "Target1.swift", line: 1,
                    message: "Unable to find module dependency: 'GRDB'",
                ),
                BuildError(
                    file: "Target2.swift", line: 1,
                    message: "Unable to find module dependency: 'GRDB'",
                ),
                BuildError(file: "Target3.swift", line: 1, message: "No such file or directory"),
            ],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        let expected = try loadSnapshot("snapshot-cascade-errors")
        expectNoDifference(formatted, expected)
    }

    @Test func `Snapshot — tests with coverage`() throws {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: 10, buildTime: nil,
                coveragePercent: 75.5,
            ),
            errors: [],
            warnings: [],
            failedTests: [],
            coverage: CodeCoverage(lineCoverage: 75.5, files: []),
        )

        let formatted = BuildResultFormatter.formatTestResult(result)
        let expected = try loadSnapshot("snapshot-test-with-coverage")
        expectNoDifference(formatted, expected)
    }
}
