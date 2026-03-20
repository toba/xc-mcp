import Testing
@testable import XCMCPCore
import Foundation

struct BuildOutputParserTests {
    @Test
    func `Parse single error`() {
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

    @Test
    func `Parse successful build`() {
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

    @Test
    func `Parse failing test`() {
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

    @Test
    func `Parse multiple errors`() {
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

    @Test
    func `Parse build time extraction`() {
        let parser = BuildOutputParser()
        let input = """
        Building for debugging...
        Build failed after 5.7 seconds
        """

        let result = parser.parse(input: input)
        #expect(result.summary.buildTime == "5.7 seconds")
    }

    @Test
    func `Parse compile error with file and line`() {
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

    @Test
    func `Passed test count from Executed summary`() {
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

    @Test
    func `Combined XCTest and Swift Testing counts`() {
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

    @Test
    func `Combined test time accumulation`() {
        let parser = BuildOutputParser()
        let input = """
        Executed 100 tests, with 0 failures (0 unexpected) in 2.500 (2.600) seconds
        Test run with 50 tests in 5 suites passed after 1.500 seconds.
        """

        let result = parser.parse(input: input)

        #expect(result.summary.testTime == "4.000s")
        #expect(result.summary.passedTests == 150)
    }

    @Test
    func `Swift compiler visual error lines are filtered`() {
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

    @Test
    func `Parse warnings`() {
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

    @Test
    func `Deduplicate identical errors`() {
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

    @Test
    func `Swift Testing summary passed`() {
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

    @Test
    func `Parse TEST FAILED flag`() {
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

    @Test
    func `FAILED with passed tests is success`() {
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

    @Test
    func `Parse fatal error`() {
        let parser = BuildOutputParser()
        let input = "TestProjectTests/TestProjectTests.swift:5: Fatal error"

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.errors.count == 1)
        #expect(result.errors[0].file == "TestProjectTests/TestProjectTests.swift")
        #expect(result.errors[0].line == 5)
        #expect(result.errors[0].message == "Fatal error")
    }

    @Test
    func `Slow test detection`() {
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

    @Test
    func `Flaky test detection`() {
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

    @Test
    func `Parse executable from RegisterWithLaunchServices`() {
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

    @Test
    func `Parse parallel test format`() {
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

    @Test
    func `Parse parallel test failure`() {
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

    @Test
    func `Swift Testing unquoted function names`() {
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

    @Test
    func `Swift Testing non-standard symbols`() {
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

    @Test
    func `Swift Testing failure summary with suites and issues`() {
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

    @Test
    func `Swift Testing failure summary singular test and issue`() {
        let parser = BuildOutputParser()
        let input = """
        Test run with 1 test in 1 suite failed after 0.500 seconds with 1 issue.
        """

        let result = parser.parse(input: input)

        #expect(result.summary.failedTests == 1)
        #expect(result.summary.passedTests == 0)
    }

    @Test
    func `Swift Testing mixed quoted and unquoted formats`() {
        let parser = BuildOutputParser()
        let input = """
        􀟈  Test shouldPass() started.
        􀟈  Test shouldFail() started.
        􁁛  Test shouldPass() passed after 0.001 seconds.
        􀢄  Test shouldFail() recorded an issue at xcsift_problemsTests.swift:9:5: Expectation failed: Bool(false)
        􀢄  Test shouldFail() failed after 0.001 seconds with 1 issue.
        􀢄  Test run with 2 tests in 0 suites failed after 0.001 seconds with 1 issue.
        """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.summary.passedTests == 1)
        #expect(result.summary.failedTests == 1)
        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "shouldFail()")
        #expect(result.failedTests[0].message == "Expectation failed: Bool(false)")
        #expect(result.failedTests[0].file == "xcsift_problemsTests.swift")
        #expect(result.failedTests[0].line == 9)
    }

    @Test
    func `Swift Testing passed with unquoted function name`() {
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
        .enabled(
            if: Bundle.module.url(
                forResource: "swift-testing-output", withExtension: "txt", subdirectory: "Fixtures",
            )
                != nil,
        ),
    )
    func `Real-world Swift Testing output`() throws {
        let parser = BuildOutputParser()

        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "swift-testing-output", withExtension: "txt", subdirectory: "Fixtures",
            ),
        )
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.errors == 0)
        #expect(result.summary.failedTests == 0)
        #expect(result.summary.passedTests == 23)
        #expect(result.summary.testTime == "0.031s")
    }

    @Test(
        .enabled(
            if: Bundle.module.url(
                forResource: "build", withExtension: "txt", subdirectory: "Fixtures",
            ) != nil,
        ),
    )
    func `Large real-world build output`() throws {
        let parser = BuildOutputParser()

        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "build", withExtension: "txt", subdirectory: "Fixtures",
            ),
        )
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        let result = parser.parse(input: input)

        #expect(result.status == "success")
        #expect(result.summary.errors == 0)
        #expect(result.summary.failedTests == 0)
    }

    // MARK: - Crash-to-test association

    @Test
    func `Crash with signal code associates with last started test`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case 'MyTests.testCrashingMethod' started.
        Exited with unexpected signal code 11
        Restarting after MyTests.testCrashingMethod
        ** TEST FAILED **
        """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "MyTests.testCrashingMethod")
        #expect(result.failedTests[0].message.contains("signal 11"))
        #expect(result.failedTests[0].message.contains("Crashed"))
    }

    @Test
    func `Crash without signal code associates with last started test`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case 'MyTests.testBadAccess' started.
        Restarting after MyTests.testBadAccess
        ** TEST FAILED **
        """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "MyTests.testBadAccess")
        #expect(result.failedTests[0].message.contains("Crashed"))
    }

    @Test
    func `Passed test clears crash tracking — no false association`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case 'MyTests.testOK' started.
        Test Case 'MyTests.testOK' passed (0.001 seconds).
        Test Case 'MyTests.testCrasher' started.
        Exited with unexpected signal code 6
        Restarting after MyTests.testCrasher
        ** TEST FAILED **
        """

        let result = parser.parse(input: input)

        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "MyTests.testCrasher")
    }

    @Test
    func `Safety net catches incomplete test when test run failed`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case 'MyTests.testHangsOrCrashes' started.
        ** TEST FAILED **
        """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "MyTests.testHangsOrCrashes")
        #expect(result.failedTests[0].message.contains("did not complete"))
    }

    @Test
    func `Safety net with pending signal code`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case 'MyTests.testSegfault' started.
        Exited with unexpected signal code 11
        ** TEST FAILED **
        """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "MyTests.testSegfault")
        #expect(result.failedTests[0].message.contains("signal 11"))
    }

    @Test
    func `No false crash for normally failed test`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case 'MyTests.testAssert' started.
        Test Case 'MyTests.testAssert' failed (0.010 seconds).
        ** TEST FAILED **
        """

        let result = parser.parse(input: input)

        #expect(result.failedTests.count == 1)
        #expect(!result.failedTests[0].message.contains("Crashed"))
    }

    @Test
    func `Swift Testing test start tracked for crash association`() {
        let parser = BuildOutputParser()
        let input = """
        ◇ Test "validateInput()" started.
        Exited with unexpected signal code 6
        Restarting after validateInput
        ** TEST FAILED **
        """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].test == "validateInput()")
        #expect(result.failedTests[0].message.contains("signal 6"))
    }

    // MARK: - Performance Measurement Parsing

    @Test
    func `Parse XCTest measure() timing data`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case '-[PerfTests.RenderTests testRenderPerformance]' started.
        /path/to/RenderTests.swift:25: Test Case '-[PerfTests.RenderTests testRenderPerformance]' measured [Time, seconds] average: 0.037, relative standard deviation: 112.254%, values: [0.125595, 0.033183, 0.015517, 0.016484, 0.015461]
        Test Case '-[PerfTests.RenderTests testRenderPerformance]' passed (2.345 seconds).
        Executed 1 test, with 0 failures (0 unexpected) in 2.345 (2.456) seconds
        """

        let result = parser.parse(input: input)

        #expect(result.performanceMeasurements.count == 1)
        let m = result.performanceMeasurements[0]
        #expect(m.test == "-[PerfTests.RenderTests testRenderPerformance]")
        #expect(m.metric == "Time, seconds")
        #expect(m.average == 0.037)
        #expect(m.relativeStandardDeviation == 112.254)
        #expect(m.values.count == 5)
        #expect(m.values[0] == 0.125595)
    }

    @Test
    func `Parse multiple measure() metrics from same test`() {
        let parser = BuildOutputParser()
        let input = """
        Test Case '-[PerfTests.MemTests testMemory]' started.
        /path/to/MemTests.swift:10: Test Case '-[PerfTests.MemTests testMemory]' measured [Time, seconds] average: 0.005, relative standard deviation: 20.0%, values: [0.006, 0.005, 0.004]
        /path/to/MemTests.swift:10: Test Case '-[PerfTests.MemTests testMemory]' measured [Memory, kB] average: 1024.0, relative standard deviation: 5.0%, values: [1000.0, 1024.0, 1048.0]
        Test Case '-[PerfTests.MemTests testMemory]' passed (1.0 seconds).
        Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.1) seconds
        """

        let result = parser.parse(input: input)

        #expect(result.performanceMeasurements.count == 2)
        #expect(result.performanceMeasurements[0].metric == "Time, seconds")
        #expect(result.performanceMeasurements[1].metric == "Memory, kB")
    }

    @Test
    func `Performance measurements included in formatted test output`() {
        let result = BuildResult(
            status: "success",
            summary: BuildSummary(
                errors: 0, warnings: 0, failedTests: 0, passedTests: 1,
                buildTime: nil, testTime: "2.3s",
            ),
            errors: [],
            warnings: [],
            failedTests: [],
            performanceMeasurements: [
                PerformanceMeasurement(
                    test: "testRender",
                    metric: "Time, seconds",
                    average: 0.037,
                    relativeStandardDeviation: 112.254,
                    values: [0.125, 0.033],
                ),
            ],
        )

        let formatted = BuildResultFormatter.formatTestResult(result)
        #expect(formatted.contains("Performance:"))
        #expect(formatted.contains("testRender"))
        #expect(formatted.contains("avg: 0.037"))
        #expect(formatted.contains("std dev: 112.3%"))
    }

    // MARK: - Swift Testing custom #expect comments

    @Test
    func `swift testing custom expect comment`() {
        let parser = BuildOutputParser()
        let result = parser.parse(input: """
        􀢄  Test "Domain stays free" recorded an issue at File.swift:16:17: Expectation failed: !(forbiddenImports.contains(import.name))
        􀄵  Domain must not import SwiftData
        􀢄  Test "Domain stays free" failed after 0.986 seconds with 1 issue.
        """)

        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].message.contains("Domain must not import SwiftData"))
        #expect(result.failedTests[0].file == "File.swift")
        #expect(result.failedTests[0].line == 16)
    }

    @Test
    func `swift testing custom expect comment linux fallback`() {
        let parser = BuildOutputParser()
        let result = parser.parse(input: """
        ✘ Test "Domain stays free" recorded an issue at File.swift:16:17: Expectation failed: !(forbiddenImports.contains(import.name))
        ↳ Domain must not import SwiftData
        ✘ Test "Domain stays free" failed after 0.986 seconds with 1 issue.
        """)

        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].message.contains("Domain must not import SwiftData"))
    }

    @Test
    func `swift testing no custom comment`() {
        let parser = BuildOutputParser()
        let result = parser.parse(input: """
        􀢄  Test shouldFail() recorded an issue at File.swift:9:5: Expectation failed: Bool(false)
        􀢄  Test shouldFail() failed after 0.001 seconds with 1 issue.
        """)

        #expect(result.failedTests.count == 1)
        #expect(result.failedTests[0].message == "Expectation failed: Bool(false)")
    }

    @Test
    func `swift testing multiple issues with comments`() {
        let parser = BuildOutputParser()
        let result = parser.parse(input: """
        􀢄  Test "test A" recorded an issue at File.swift:10:5: Expectation failed: A
        􀄵  Comment A
        􀢄  Test "test B" recorded an issue at File.swift:20:5: Expectation failed: B
        􀄵  Comment B
        """)

        #expect(result.failedTests.count == 2)
        #expect(result.failedTests[0].message.contains("Comment A"))
        #expect(result.failedTests[1].message.contains("Comment B"))
    }
}
