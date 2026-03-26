import Testing
@testable import XCMCPCore
import Foundation

struct XCResultParserTests {
    @Test
    func `Non-existent path returns nil`() async {
        let result = await XCResultParser.parseTestResults(at: "/nonexistent/path.xcresult")
        #expect(result == nil)
    }
}

struct ErrorExtractorInfrastructureTests {
    @Test
    func `Detects testmanagerd SIGSEGV crash`() async throws {
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
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: testmanagerd crashed"))
    }

    @Test
    func `Detects testmanagerd EXC_BAD_ACCESS`() async throws {
        let stderr = "testmanagerd: EXC_BAD_ACCESS in HIServices"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: testmanagerd crashed"))
    }

    @Test
    func `Detects testmanagerd lost connection`() async throws {
        let stderr = "testmanagerd lost connection to test process"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: testmanagerd terminated unexpectedly"))
    }

    @Test
    func `No warning for clean stderr`() async throws {
        let stderr = "note: Using new build system"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(!text.contains("Warning:"))
    }

    @Test
    func `No warning when stderr is nil`() async throws {
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(!text.contains("Warning:"))
    }

    @Test
    func `Failed tests throw MCPError with warning appended`() async {
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

    @Test
    func `Detects IDETestRunnerDaemon crash`() async throws {
        let stderr = "IDETestRunnerDaemon crash report generated"
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            stderr: stderr,
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Warning: The test runner daemon crashed"))
    }
}

struct ErrorExtractorZeroTestTests {
    @Test
    func `Errors when only_testing filter matches zero tests`() async {
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

    @Test
    func `Succeeds when only_testing filter matches tests`() async throws {
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Standard' on macOS",
            onlyTesting: ["MathViewTests/AnalysisTests/analysis(_:)"],
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Tests passed"))
    }

    @Test
    func `No error when no only_testing filter and zero tests`() async throws {
        // Without only_testing, zero tests is not an error (could be a legitimate empty test target)
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run completed.",
            succeeded: true,
            context: "scheme 'Standard' on macOS",
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Test run completed"))
    }

    @Test
    func `Error message includes all filter identifiers`() async {
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

struct ErrorExtractorExitCodeOverrideTests {
    @Test
    func `Succeeds when exit code is non-zero but parsed output shows tests passed`() async throws {
        // Reproduces the bug: swift test exits non-zero but all tests pass
        let output = """
        Building for debugging...
        Build complete!
        Test Suite 'All tests' started.
        Test Suite 'PackageTests' passed at 2026-03-01 10:00:00.
        Executed 4535 tests, with 0 failures (0 unexpected) in 12.345 (12.567) seconds
        """
        let result = try await ErrorExtractor.formatTestToolResult(
            output: output,
            succeeded: false, // non-zero exit code
            context: "swift package",
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Tests passed"))
    }

    @Test
    func `Still fails when exit code is non-zero and tests actually failed`() async {
        let output = """
        Test Case 'FooTests.testBar' failed (0.5 seconds)
        Executed 10 tests, with 2 failures (2 unexpected) in 1.234 (1.500) seconds
        """
        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: output,
                succeeded: false,
                context: "swift package",
            )
            Issue.record("Expected error to be thrown for failing tests")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Tests failed") || message.contains("failed"))
        }
    }
}
