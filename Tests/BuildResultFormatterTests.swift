import Testing
@testable import XCMCPCore
import Foundation

struct BuildResultFormatterTests {
    @Test
    func `Format successful build`() {
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

    @Test
    func `Format failed build with errors`() {
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
                ),
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

    @Test
    func `Format test results passed`() {
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

    @Test
    func `Format test results with failures`() {
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

    @Test
    func `Format linker errors`() {
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
                ),
            ],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        #expect(formatted.contains("Linker errors:"))
        #expect(formatted.contains("_MissingFunc"))
        #expect(formatted.contains("arm64"))
    }

    @Test
    func `Format coverage in test results`() {
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

    @Test
    func `ErrorExtractor.extractBuildErrors integration`() {
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

    @Test
    func `Failed build with project root filters external warnings`() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 1, warnings: 3, failedTests: 0, passedTests: nil, buildTime: "8.2s",
            ),
            errors: [
                BuildError(
                    file: "/Users/dev/MyApp/Sources/App.swift", line: 10,
                    message: "missing import", column: 1,
                ),
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

    @Test
    func `Successful build with project root omits all warnings`() {
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

    @Test
    func `Nil project root preserves all warnings (backwards compat)`() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 1, warnings: 2, failedTests: 0, passedTests: nil, buildTime: nil,
            ),
            errors: [
                BuildError(file: "main.swift", line: 1, message: "error"),
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

    @Test
    func `Warnings without file path are always shown`() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 1, warnings: 2, failedTests: 0, passedTests: nil, buildTime: nil,
            ),
            errors: [
                BuildError(file: nil, line: nil, message: "some error"),
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

    @Test
    func `ErrorExtractor.extractBuildErrors threads project root`() {
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

    @Test
    func `Format test results always includes both passed and failed counts`() {
        let allPassed = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: 12, buildTime: nil,
                testTime: "1.0s",
            ),
            errors: [],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatTestResult(allPassed)
        #expect(formatted.contains("12 passed"))
        #expect(formatted.contains("0 failed"))
    }

    @Test
    func `ErrorExtractor.extractTestResults integration`() {
        let output = """
        Test Case 'MyTests.testA' passed (0.001 seconds).
        Test Case 'MyTests.testB' passed (0.002 seconds).
        Executed 2 tests, with 0 failures (0 unexpected) in 0.003 (0.005) seconds
        """

        let formatted = ErrorExtractor.extractTestResults(from: output)
        #expect(formatted.contains("Tests passed"))
        #expect(formatted.contains("2 passed"))
    }

    // MARK: - Cascade Error Truncation

    @Test
    func `Script phase failure truncates cascade errors`() {
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
                BuildError(
                    file: "Target3.swift", line: 1,
                    message: "No such file or directory",
                ),
            ],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        // Root cause is shown
        #expect(formatted.contains("PhaseScriptExecution failed"))
        // Cascade errors are hidden
        #expect(!formatted.contains("Unable to find module dependency"))
        #expect(!formatted.contains("No such file or directory"))
        // Summary of hidden cascade errors
        #expect(formatted.contains("+3 cascade errors from downstream targets hidden"))
    }

    @Test
    func `No cascade truncation without script phase failure`() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 2, warnings: 0, failedTests: 0, passedTests: nil, buildTime: nil,
            ),
            errors: [
                BuildError(
                    file: "Foo.swift", line: 1,
                    message: "Unable to find module dependency: 'Bar'",
                ),
                BuildError(file: "Baz.swift", line: 2, message: "missing return"),
            ],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        // Without a script phase failure, all errors are shown
        #expect(formatted.contains("Unable to find module dependency"))
        #expect(formatted.contains("missing return"))
        #expect(!formatted.contains("cascade"))
    }

    @Test
    func `Cascade truncation singular form`() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 2, warnings: 0, failedTests: 0, passedTests: nil, buildTime: nil,
            ),
            errors: [
                BuildError(
                    file: nil, line: nil,
                    message: "Command PhaseScriptExecution failed with a nonzero exit code",
                ),
                BuildError(
                    file: "Target.swift", line: 1,
                    message: "Unable to find module dependency: 'Foo'",
                ),
            ],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(result)
        #expect(formatted.contains("+1 cascade error from downstream targets hidden"))
    }

    // MARK: - Status Override (timeout/stuck builds)

    @Test
    func `Status override replaces Build succeeded header`() {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 5, failedTests: 0, passedTests: nil, buildTime: "45.2s",
            ),
            errors: [],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(
            result, statusOverride: "Build interrupted (did not complete)",
        )
        #expect(formatted.contains("Build interrupted (did not complete)"))
        #expect(!formatted.contains("Build succeeded"))
        // Counts still present
        #expect(formatted.contains("5 warning"))
        #expect(formatted.contains("45.2s"))
    }

    @Test
    func `Status override replaces Build failed header`() {
        let result = BuildResult(
            status: "failed",
            summary: BuildSummary(
                errors: 2, warnings: 0, failedTests: 0, passedTests: nil, buildTime: nil,
            ),
            errors: [
                BuildError(file: "Foo.swift", line: 1, message: "type error"),
                BuildError(file: "Bar.swift", line: 2, message: "missing return"),
            ],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(
            result, statusOverride: "Build interrupted (did not complete)",
        )
        #expect(formatted.contains("Build interrupted (did not complete)"))
        #expect(!formatted.contains("Build failed"))
        // Errors still shown
        #expect(formatted.contains("type error"))
        #expect(formatted.contains("missing return"))
    }

    @Test
    func `Nil status override preserves default header`() {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: nil, buildTime: "1.0s",
            ),
            errors: [],
            warnings: [],
            failedTests: [],
        )

        let formatted = BuildResultFormatter.formatBuildResult(
            result, statusOverride: nil,
        )
        #expect(formatted.contains("Build succeeded"))
    }

    @Test
    func `formatPartialDiagnostics uses interrupted header not Build succeeded`() {
        let error = XcodebuildError.timeout(
            duration: 60,
            partialOutput: """
            /src/Foo.swift:10:5: warning: unused variable 'x'
            Build succeeded
            """,
        )

        let result = error.formatPartialDiagnostics(projectRoot: nil)
        var text = ""
        if case let .text(t, _, _) = result.content[0] { text = t }
        #expect(text.contains("Build timed out after 60 seconds"))
        #expect(text.contains("Build interrupted (did not complete)"))
        // The formatted header must NOT say "Build succeeded" — only "Build interrupted"
        // (The raw partial output is not appended when diagnostics are present)
        #expect(!text.contains("Build succeeded"))
        #expect(result.isError == true)
    }

    @Test
    func `formatPartialDiagnostics for stuck process uses interrupted header`() {
        let error = XcodebuildError.stuckProcess(
            noOutputFor: 30,
            partialOutput: """
            /src/Bar.swift:5:1: warning: deprecated API
            Build succeeded
            """,
        )

        let result = error.formatPartialDiagnostics(projectRoot: nil)
        var text = ""
        if case let .text(t, _, _) = result.content[0] { text = t }
        #expect(text.contains("Build appears stuck"))
        #expect(text.contains("Build interrupted (did not complete)"))
        #expect(!text.contains("Build succeeded"))
        #expect(result.isError == true)
    }

    // MARK: - Realistic timeout scenarios (what an agent actually sees)

    @Test
    func `Realistic timeout with warnings mimics Thesis build`() {
        // Simulates a real project that compiles with warnings but times out
        let error = XcodebuildError.timeout(
            duration: 30,
            partialOutput: """
            CompileSwift normal arm64 /Users/dev/thesis/Sources/Views/ContentView.swift
            CompileSwift normal arm64 /Users/dev/thesis/Sources/Models/Document.swift
            /Users/dev/thesis/Sources/Views/ContentView.swift:45:12: warning: immutable value 'result' was never used; consider replacing with '_' or removing it
            /Users/dev/thesis/Sources/Views/ContentView.swift:102:8: warning: expression of type 'Bool' is unused
            /Users/dev/thesis/Sources/Models/Document.swift:23:5: warning: 'init(from:)' is deprecated
            CompileSwift normal arm64 /Users/dev/thesis/Sources/App/ThesisApp.swift
            /Users/dev/thesis/Sources/App/ThesisApp.swift:15:20: warning: will never be executed
            Linking Thesis
            GenerateDSYMFile /Users/dev/DerivedData/Build/Products/Debug/Thesis.app.dSYM /Users/dev/DerivedData/Build/Products/Debug/Thesis.app/Contents/MacOS/Thesis
            Touch /Users/dev/DerivedData/Build/Products/Debug/Thesis.app
            RegisterExecutionPolicyException /Users/dev/DerivedData/Build/Products/Debug/Thesis.app
            ** BUILD SUCCEEDED **
            """,
        )

        let result = error.formatPartialDiagnostics(
            projectRoot: "/Users/dev/thesis", errorsOnly: true,
        )
        var text = ""
        if case let .text(t, _, _) = result.content[0] { text = t }

        // Agent must see "interrupted", never "succeeded"
        #expect(text.contains("Build interrupted (did not complete)"))
        #expect(!text.contains("Build succeeded"))
        #expect(!text.contains("BUILD SUCCEEDED"))
        // Timeout header is present
        #expect(text.contains("Build timed out after 30 seconds"))
        // isError so agent knows it's not a success
        #expect(result.isError == true)

        // Print what the agent actually sees
        print("--- Agent sees this output ---")
        print(text)
        print("--- End agent output ---")
    }

    @Test
    func `Stuck build with compilation progress shows target info`() {
        // Simulates a build that stalls during compilation — the progress
        // summary should show which targets are in progress
        let error = XcodebuildError.stuckProcess(
            noOutputFor: 30,
            partialOutput: """
            SwiftDriver GRDBCustom normal arm64 com.apple.xcode.tools.swift.compiler (in target 'GRDBCustom' from project 'GRDBCustom')
            SwiftDriver Core normal arm64 com.apple.xcode.tools.swift.compiler (in target 'Core' from project 'Thesis')
            Linking GRDB (in target 'GRDBCustom' from project 'GRDBCustom')
            """,
        )

        let result = error.formatPartialDiagnostics(projectRoot: "/Users/dev/thesis")
        var text = ""
        if case let .text(t, _, _) = result.content[0] { text = t }

        // Must show build progress
        #expect(text.contains("Build progress when interrupted:"))
        #expect(text.contains("In progress:"))
        #expect(text.contains("Core"))
        #expect(text.contains("Completed: GRDB"))
        // Must NOT dump build settings
        #expect(!text.contains("PRODUCT_NAME"))
        // Header is correct
        #expect(text.contains("Build interrupted (did not complete)"))
        #expect(text.contains("Build appears stuck"))
        #expect(result.isError == true)

        print("--- Agent sees this output ---")
        print(text)
        print("--- End agent output ---")
    }
}
