import Testing
@testable import XCMCPCore
import Foundation

@Suite("XCResultParser Tests")
struct XCResultParserTests {
    @Test("Non-existent path returns nil")
    func nonExistentPath() async {
        let result = await XCResultParser.parseTestResults(at: "/nonexistent/path.xcresult")
        #expect(result == nil)
    }
}

@Suite("ErrorExtractor Infrastructure Warning Tests")
struct ErrorExtractorInfrastructureTests {
    @Test("Detects testmanagerd SIGSEGV crash")
    func managerdSIGSEGV() async throws {
        let stderr = """
        Testing started
        testmanagerd received SIGSEGV: pointer authentication failure
        """
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: testmanagerd crashed"))
    }

    @Test("Detects testmanagerd EXC_BAD_ACCESS")
    func managerdExcBadAccess() async throws {
        let stderr = "testmanagerd: EXC_BAD_ACCESS in HIServices"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: testmanagerd crashed"))
    }

    @Test("Detects testmanagerd lost connection")
    func managerdLostConnection() async throws {
        let stderr = "testmanagerd lost connection to test process"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: testmanagerd terminated unexpectedly"))
    }

    @Test("No warning for clean stderr")
    func cleanStderr() async throws {
        let stderr = "note: Using new build system"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(!text.contains("Warning:"))
    }

    @Test("No warning when stderr is nil")
    func nilStderr() async throws {
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(!text.contains("Warning:"))
    }

    @Test("Failed tests throw MCPError with warning appended")
    func failedWithWarning() async {
        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: """
                Test Case 'FooTests.testBar' failed (0.5 seconds)
                Executed 1 test, with 1 failure in 0.5 seconds
                """,
                succeeded: false,
                context: "scheme 'Foo' on macOS",
                stderr: "testmanagerd received SIGSEGV",
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    @Test("Detects IDETestRunnerDaemon crash")
    func iDETestRunnerDaemonCrash() async throws {
        let stderr = "IDETestRunnerDaemon crash report generated"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: The test runner daemon crashed"))
    }
}

@Suite("ErrorExtractor Zero-Test Detection Tests")
struct ErrorExtractorZeroTestTests {
    @Test("Errors when only_testing filter matches zero tests")
    func zeroTestsWithOnlyTesting() async {
        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: "Test run completed.",
                succeeded: true,
                context: "scheme 'Standard' on macOS",
                onlyTesting: ["MathViewTests/WrongName/analysis(_:)"],
            )
            Issue.record("Expected error to be thrown for zero-test run with only_testing")
        } catch {
            let message = "\(error)"
            #expect(message.contains("No tests matched the only_testing filter"))
            #expect(message.contains("WrongName"))
        }
    }

    @Test("Succeeds when only_testing filter matches tests")
    func testsRunWithOnlyTesting() async throws {
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Standard' on macOS",
            onlyTesting: ["MathViewTests/AnalysisTests/analysis(_:)"],
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Tests passed"))
    }

    @Test("No error when no only_testing filter and zero tests")
    func zeroTestsWithoutFilter() async throws {
        // Without only_testing, zero tests is not an error (could be a legitimate empty test target)
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run completed.",
            succeeded: true,
            context: "scheme 'Standard' on macOS",
        )
        let text = result.content.compactMap {
            if case let .text(t) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Test run completed"))
    }

    @Test("Error message includes all filter identifiers")
    func multipleFilters() async {
        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: "Test run completed.",
                succeeded: true,
                context: "scheme 'Standard' on macOS",
                onlyTesting: ["Target/WrongA", "Target/WrongB"],
            )
            Issue.record("Expected error to be thrown")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Target/WrongA"))
            #expect(message.contains("Target/WrongB"))
        }
    }
}
