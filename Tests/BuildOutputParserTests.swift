import Foundation
import Testing

@testable import XCMCPCore

@Suite("BuildOutputParser Tests")
struct BuildOutputParserTests {
    @Test("Parse single error")
    func testParseError() {
        let parser = BuildOutputParser()
        let input = """
            main.swift:15:5: error: use of undeclared identifier 'unknown'
            unknown = 5
            ^
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.summary.errors == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].file == "main.swift")
        #expect(result.errors[0].line == 15)
        #expect(result.errors[0].message == "use of undeclared identifier 'unknown'")
    }

    @Test("Parse successful build")
    func testParseSuccessfulBuild() {
        let parser = BuildOutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.errors == 0)
        #expect(result.summary.failedTests == 0)
        #expect(result.summary.passedTests == nil)
    }

    @Test("Parse failing test")
    func testFailingTest() {
        let parser = BuildOutputParser()
        let input = """
            Test Case 'LoginTests.testInvalidCredentials' failed (0.045 seconds).
            XCTAssertEqual failed: Expected valid login
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.summary.failedTests == 2)
        #expect(result.failedTests.count == 2)
        #expect(result.failedTests[0].test == "LoginTests.testInvalidCredentials")
        #expect(result.failedTests[1].test == "Test assertion")
    }

    @Test("Parse multiple errors")
    func testMultipleErrors() {
        let parser = BuildOutputParser()
        let input = """
            UserService.swift:45:12: error: cannot find 'invalidFunction' in scope
            NetworkManager.swift:23:5: error: use of undeclared identifier 'unknownVariable'
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.summary.errors == 2)
        #expect(result.errors.count == 2)
    }

    @Test("Parse build time extraction")
    func testBuildTimeExtraction() {
        let parser = BuildOutputParser()
        let input = """
            Building for debugging...
            Build failed after 5.7 seconds
            """

        let result = parser.parse(input: input)
        #expect(result.summary.buildTime == "5.7 seconds")
    }

    @Test("Parse compile error with file and line")
    func testParseCompileError() {
        let parser = BuildOutputParser()
        let input = """
            UserManager.swift:42:10: error: cannot find 'undefinedVariable' in scope
            print(undefinedVariable)
            ^
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.summary.errors == 1)
        #expect(result.errors[0].file == "UserManager.swift")
        #expect(result.errors[0].line == 42)
        #expect(result.errors[0].message == "cannot find 'undefinedVariable' in scope")
    }

    @Test("Passed test count from Executed summary")
    func testPassedTestCountFromExecutedSummary() {
        let parser = BuildOutputParser()
        let input = """
            Test Case 'SampleTests.testExample' passed (0.001 seconds).
            Executed 5 tests, with 0 failures (0 unexpected) in 5.017 (5.020) seconds
            """

        let result = parser.parse(input: input)

        #expect(result.summary.passedTests == 5)
        #expect(result.summary.failedTests == 0)
        #expect(result.summary.testTime == "5.017s")
    }

    @Test("Combined XCTest and Swift Testing counts")
    func testCombinedXCTestAndSwiftTestingCounts() {
        let parser = BuildOutputParser()
        let input = """
            Test Suite 'All tests' started at 2024-01-01 12:00:00.000.
            Test Case '-[MyPackageTests.MyXCTests testExample1]' passed (0.001 seconds).
            Test Case '-[MyPackageTests.MyXCTests testExample2]' passed (0.001 seconds).
            Executed 1624 tests, with 0 failures (0 unexpected) in 2.728 (2.768) seconds
            ✓ Test "SwiftTest1" passed after 0.001 seconds.
            ✓ Test "SwiftTest2" passed after 0.001 seconds.
            ✓ Test "SwiftTest3" passed after 0.001 seconds.
            Test run with 82 tests in 7 suites passed after 0.166 seconds.
            """

        let result = parser.parse(input: input)

        #expect(result.summary.passedTests == 1624 + 82)
        #expect(result.summary.failedTests == 0)
        #expect(result.status == "success")
    }

    @Test("Combined test time accumulation")
    func testCombinedTestTimeAccumulation() {
        let parser = BuildOutputParser()
        let input = """
            Executed 100 tests, with 0 failures (0 unexpected) in 2.500 (2.600) seconds
            Test run with 50 tests in 5 suites passed after 1.500 seconds.
            """

        let result = parser.parse(input: input)

        #expect(result.summary.testTime == "4.000s")
        #expect(result.summary.passedTests == 150)
    }

    @Test("Swift compiler visual error lines are filtered")
    func testSwiftCompilerVisualErrorLinesAreFiltered() {
        let parser = BuildOutputParser()
        let input = """
            /Users/test/project/Tests/TestFile.swift:16:34: error: missing argument for parameter 'fragments' in call
             14 |             kind: "class",
             15 |             language: "swift",
             16 |             structuredContent: []
                |                                  `- error: missing argument for parameter 'fragments' in call
             17 |         )
             18 |
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.summary.errors == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].file == "/Users/test/project/Tests/TestFile.swift")
        #expect(result.errors[0].line == 16)
    }

    @Test("Parse warnings")
    func testParseWarning() {
        let parser = BuildOutputParser()
        let input = """
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.warnings == 1)
        #expect(result.warnings[0].file == "AppDelegate.swift")
        #expect(result.warnings[0].line == 67)
        #expect(result.warnings[0].message == "unused variable 'config'")
    }

    @Test("Deduplicate identical errors")
    func testParseDuplicateErrors() {
        let parser = BuildOutputParser()
        let input = """
            /path/to/File.swift:10:5: error: use of undeclared identifier
            /path/to/File.swift:10:5: error: use of undeclared identifier
            /path/to/Other.swift:20:1: error: different error
            """

        let result = parser.parse(input: input)

        #expect(result.summary.errors == 2)
        #expect(result.errors.count == 2)
    }

    @Test("Swift Testing summary passed")
    func testSwiftTestingSummaryPassed() {
        let parser = BuildOutputParser()
        let input = """
            ✓ Test "test1" passed after 0.022 seconds.
            ✓ Test "test2" passed after 0.022 seconds.
            ✓ Test "test3" passed after 0.023 seconds.
            Test run with 23 tests in 5 suites passed after 0.031 seconds.
            """

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.passedTests == 23)
        #expect(result.summary.failedTests == 0)
        #expect(result.summary.testTime == "0.031s")
    }

    @Test("Parse TEST FAILED flag")
    func testParseTestFailed() {
        let parser = BuildOutputParser()
        let input = """
            Test Case '-[TestProjectTests.TestProjectTests testExample]' started.
            TestProjectTests/TestProjectTests.swift:5: Fatal error
            Restarting after unexpected exit, crash, or test timeout
            ** TEST FAILED **
            """

        let result = parser.parse(input: input)
        #expect(result.status == "failed")
    }

    @Test("TEST FAILED with passed tests is success")
    func testParseTestFailedWithPassedTests() {
        let parser = BuildOutputParser()
        let input = """
            Building for testing...
            Build complete!
            Test Case 'MyTests.testExample' passed (0.001 seconds).
            Test Case 'MyTests.testAnother' passed (0.002 seconds).
            Executed 2 tests, with 0 failures in 0.003 seconds
            ** TEST FAILED **
            """

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.failedTests.isEmpty)
        #expect(result.summary.passedTests == 2)
    }

    @Test("Parse fatal error")
    func testParseFatalError() {
        let parser = BuildOutputParser()
        let input = "TestProjectTests/TestProjectTests.swift:5: Fatal error"

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.errors.count == 1)
        #expect(result.errors[0].file == "TestProjectTests/TestProjectTests.swift")
        #expect(result.errors[0].line == 5)
        #expect(result.errors[0].message == "Fatal error")
    }

    @Test("Slow test detection")
    func testSlowTestDetection() {
        let parser = BuildOutputParser()
        let input = """
            Test Case 'SampleTests.testFast' passed (0.1 seconds).
            Test Case 'SampleTests.testSlow' passed (5.0 seconds).
            """

        let result = parser.parse(input: input, slowThreshold: 1.0)

        #expect(result.slowTests.count == 1)
        #expect(result.slowTests[0].test == "SampleTests.testSlow")
        #expect(result.slowTests[0].duration == 5.0)
    }

    @Test("Flaky test detection")
    func testFlakyTestDetection() {
        let parser = BuildOutputParser()
        let input = """
            Test Case 'SampleTests.testFlakyTest' passed (0.1 seconds).
            Test Case 'SampleTests.testFlakyTest' failed (0.2 seconds).
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.flakyTests.count == 1)
        #expect(result.flakyTests.contains("SampleTests.testFlakyTest"))
    }

    @Test("Parse executable from RegisterWithLaunchServices")
    func testParseExecutable() {
        let parser = BuildOutputParser()
        let input = """
            RegisterWithLaunchServices /path/to/MyApp.app (in target 'MyApp' from project 'MyProject')
            """

        let result = parser.parse(input: input)

        #expect(result.executables.count == 1)
        #expect(result.executables[0].path == "/path/to/MyApp.app")
        #expect(result.executables[0].name == "MyApp.app")
        #expect(result.executables[0].target == "MyApp")
    }

    @Test("Parse parallel test format")
    func testParseParallelTestingPassedFormat() {
        let parser = BuildOutputParser()
        let input = """
            Test case 'MenuBarFeatureTests.testExample()' passed on 'My Mac - App (Dev) (51424)' (0.565 seconds)
            Test case 'FilesChannelTests.testAnother()' passed on 'My Mac - App (Dev) (52255)' (0.002 seconds)
            Executed 2 tests, with 0 failures in 0.567 seconds
            ** TEST SUCCEEDED **
            """

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.passedTests == 2)
        #expect(result.failedTests.isEmpty)
    }

    @Test("Parse parallel test failure")
    func testParseParallelTestingFailedFormat() {
        let parser = BuildOutputParser()
        let input = """
            Test case 'PublishingServiceTests.testProcessEntry()' failed on 'My Mac - App (Dev) (51424)' (0.070 seconds)
            Executed 1 test, with 1 failure in 0.070 seconds
            ** TEST FAILED **
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "PublishingServiceTests.testProcessEntry()")
        #expect(result.failedTests[0].duration == 0.070)
    }

    @Test("Swift Testing unquoted function names")
    func testSwiftTestingUnquotedFunctionNames() {
        let parser = BuildOutputParser()
        let input = """
            ◇ Test functionName() recorded an issue at /path/to/File.swift:42:10: expected true
            ✘ Test anotherFunc() failed after 1.234 seconds with 2 issues.
            """

        let result = parser.parse(input: input)

        #expect(result.failedTests.count == 2)
        #expect(result.failedTests[0].test == "functionName()")
        #expect(result.failedTests[0].file == "/path/to/File.swift")
        #expect(result.failedTests[0].line == 42)
        #expect(result.failedTests[0].message == "expected true")
        #expect(result.failedTests[1].test == "anotherFunc()")
        #expect(result.failedTests[1].duration == 1.234)
    }

    @Test("Swift Testing non-standard symbols")
    func testSwiftTestingNonStandardSymbols() {
        let parser = BuildOutputParser()
        let input = """
            ◇ Test "test1" passed after 0.010 seconds.
            ▷ Test "test2" passed after 0.020 seconds.
            Test run with 2 tests in 1 suite passed after 0.030 seconds.
            """

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.passedTests == 2)
        #expect(result.summary.testTime == "0.030s")
    }

    @Test("Swift Testing failure summary with suites and issues")
    func testSwiftTestingFailureSummaryWithSuitesAndIssues() {
        let parser = BuildOutputParser()
        let input = """
            ✘ Test "failingTest" recorded an issue at /path/File.swift:10:5: assertion failed
            Test run with 5 tests in 2 suites failed after 1.500 seconds with 3 issues.
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.summary.passedTests == 5 - 3)
        #expect(result.summary.failedTests == 3)
        #expect(result.summary.testTime == "1.500s")
    }

    @Test("Swift Testing failure summary singular test and issue")
    func testSwiftTestingFailureSummarySingular() {
        let parser = BuildOutputParser()
        let input = """
            Test run with 1 test in 1 suite failed after 0.500 seconds with 1 issue.
            """

        let result = parser.parse(input: input)

        #expect(result.summary.failedTests == 1)
        #expect(result.summary.passedTests == 0)
    }

    @Test("Swift Testing passed with unquoted function name")
    func testSwiftTestingPassedUnquotedFunctionName() {
        let parser = BuildOutputParser()
        let input = """
            ✓ Test myTestFunction() passed after 0.050 seconds.
            Test run with 1 test in 1 suite passed after 0.050 seconds.
            """

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.passedTests == 1)
    }

    @Test(
        "Real-world Swift Testing output",
        .enabled(
            if: Bundle.module.url(
                forResource: "swift-testing-output", withExtension: "txt", subdirectory: "Fixtures")
                != nil))
    func testRealWorldSwiftTestingOutput() throws {
        let parser = BuildOutputParser()

        let fixtureURL = Bundle.module.url(
            forResource: "swift-testing-output", withExtension: "txt", subdirectory: "Fixtures")!
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.errors == 0)
        #expect(result.summary.failedTests == 0)
        #expect(result.summary.passedTests == 23)
        #expect(result.summary.testTime == "0.031s")
    }

    @Test(
        "Large real-world build output",
        .enabled(
            if: Bundle.module.url(
                forResource: "build", withExtension: "txt", subdirectory: "Fixtures") != nil))
    func testLargeRealWorldBuildOutput() throws {
        let parser = BuildOutputParser()

        let fixtureURL = Bundle.module.url(
            forResource: "build", withExtension: "txt", subdirectory: "Fixtures")!
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.errors == 0)
        #expect(result.summary.failedTests == 0)
    }
}
