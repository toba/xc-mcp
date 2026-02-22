import Testing

@testable import XCMCPCore

@Suite("BuildResultFormatter Tests")
struct BuildResultFormatterTests {
  @Test("Format successful build")
  func formatSuccessfulBuild() {
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
    #expect(formatted.contains("Build succeeded"))
    #expect(formatted.contains("2.3s"))
  }

  @Test("Format failed build with errors")
  func formatFailedBuild() {
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
        BuildWarning(
          file: "Baz.swift",
          line: 88,
          message: "unused variable 'x'",
          column: 3,
        )
      ],
      failedTests: [],
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
  func formatTestResultsPassed() {
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
    #expect(formatted.contains("Tests passed"))
    #expect(formatted.contains("42 passed"))
    #expect(formatted.contains("3.2s"))
  }

  @Test("Format test results with failures")
  func formatTestResultsFailed() {
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
          test: "MyTests.testLogout", message: "Timeout after 5.0s", file: nil, line: nil,
        ),
      ],
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
  func formatLinkerErrors() {
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
        LinkerError(
          symbol: "_MissingFunc",
          architecture: "arm64",
          referencedFrom: "main.o",
        )
      ],
    )

    let formatted = BuildResultFormatter.formatBuildResult(result)
    #expect(formatted.contains("Linker errors:"))
    #expect(formatted.contains("_MissingFunc"))
    #expect(formatted.contains("arm64"))
  }

  @Test("Format coverage in test results")
  func formatCoverageInTestResults() {
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
    #expect(formatted.contains("Coverage: 75.5%"))
  }

  @Test("ErrorExtractor.extractBuildErrors integration")
  func errorExtractorIntegration() {
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

  // MARK: - Project Root Warning Filtering

  @Test("Failed build with project root filters external warnings")
  func failedBuildFiltersExternalWarnings() {
    let result = BuildResult(
      status: "failed",
      summary: BuildSummary(
        errors: 1, warnings: 3, failedTests: 0, passedTests: nil, buildTime: "8.2s",
      ),
      errors: [
        BuildError(
          file: "/Users/dev/MyApp/Sources/App.swift", line: 10,
          message: "missing import", column: 1,
        )
      ],
      warnings: [
        BuildWarning(
          file: "/Users/dev/MyApp/Sources/Foo.swift", line: 5,
          message: "unused variable 'x'",
        ),
        BuildWarning(
          file: "/Users/dev/MyApp/Pods/SomeLib/Source.swift", line: 20,
          message: "deprecated API",
        ),
        BuildWarning(
          file: "/Users/dev/DerivedData/Build/SomeOther.swift", line: 99,
          message: "implicit conversion",
        ),
      ],
      failedTests: [],
    )

    let formatted = BuildResultFormatter.formatBuildResult(
      result, projectRoot: "/Users/dev/MyApp",
    )
    // Project warning is shown
    #expect(formatted.contains("unused variable 'x'"))
    // Pods warning is shown (inside project root)
    #expect(formatted.contains("deprecated API"))
    // DerivedData warning is hidden
    #expect(!formatted.contains("implicit conversion"))
    // Summary of hidden warnings
    #expect(formatted.contains("(+1 warning from dependencies hidden)"))
  }

  @Test("Successful build with project root omits all warnings")
  func successfulBuildOmitsWarnings() {
    let result = BuildResult(
      status: "success",
      summary: BuildSummary(
        errors: 0, warnings: 5, failedTests: 0, passedTests: nil, buildTime: "3.0s",
      ),
      errors: [],
      warnings: [
        BuildWarning(
          file: "/Users/dev/MyApp/Sources/Foo.swift", line: 1,
          message: "unused var",
        ),
        BuildWarning(
          file: "/external/Lib/Bar.swift", line: 2,
          message: "deprecated",
        ),
      ],
      failedTests: [],
    )

    let formatted = BuildResultFormatter.formatBuildResult(
      result, projectRoot: "/Users/dev/MyApp",
    )
    #expect(formatted.contains("Build succeeded"))
    #expect(formatted.contains("5 warning"))
    // No warning details shown on success
    #expect(!formatted.contains("unused var"))
    #expect(!formatted.contains("deprecated"))
    #expect(!formatted.contains("Warnings:"))
  }

  @Test("Nil project root preserves all warnings (backwards compat)")
  func nilProjectRootPreservesAllWarnings() {
    let result = BuildResult(
      status: "failed",
      summary: BuildSummary(
        errors: 1, warnings: 2, failedTests: 0, passedTests: nil, buildTime: nil,
      ),
      errors: [
        BuildError(file: "main.swift", line: 1, message: "error")
      ],
      warnings: [
        BuildWarning(
          file: "/external/Lib.swift", line: 1,
          message: "external warning",
        ),
        BuildWarning(
          file: "/project/Source.swift", line: 2,
          message: "project warning",
        ),
      ],
      failedTests: [],
    )

    let formatted = BuildResultFormatter.formatBuildResult(result)
    #expect(formatted.contains("external warning"))
    #expect(formatted.contains("project warning"))
    #expect(!formatted.contains("dependencies hidden"))
  }

  @Test("Warnings without file path are always shown")
  func warningsWithoutFileAlwaysShown() {
    let result = BuildResult(
      status: "failed",
      summary: BuildSummary(
        errors: 1, warnings: 2, failedTests: 0, passedTests: nil, buildTime: nil,
      ),
      errors: [
        BuildError(file: nil, line: nil, message: "some error")
      ],
      warnings: [
        BuildWarning(file: nil, line: nil, message: "unlocalized warning"),
        BuildWarning(
          file: "/external/Dep/File.swift", line: 1,
          message: "dep warning",
        ),
      ],
      failedTests: [],
    )

    let formatted = BuildResultFormatter.formatBuildResult(
      result, projectRoot: "/Users/dev/MyApp",
    )
    // Warning without file is shown
    #expect(formatted.contains("unlocalized warning"))
    // External warning is hidden
    #expect(!formatted.contains("dep warning"))
    #expect(formatted.contains("(+1 warning from dependencies hidden)"))
  }

  @Test("ErrorExtractor.extractBuildErrors threads project root")
  func errorExtractorThreadsProjectRoot() {
    let output = """
      /ext/Lib.swift:1:1: warning: external warning
      /proj/App.swift:10:5: error: missing import
      """

    let formatted = ErrorExtractor.extractBuildErrors(
      from: output, projectRoot: "/proj",
    )
    #expect(!formatted.contains("external warning"))
    #expect(formatted.contains("missing import"))
    #expect(formatted.contains("dependencies hidden"))
  }

  @Test("ErrorExtractor.extractTestResults integration")
  func errorExtractorTestResultsIntegration() {
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
