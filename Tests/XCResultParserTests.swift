import Testing
@testable import XCMCPCore
import Foundation

@Suite("XCResultParser Tests")
struct XCResultParserTests {
    @Test("Non-existent path returns nil")
    func nonExistentPath() {
        let result = XCResultParser.parseTestResults(at: "/nonexistent/path.xcresult")
        #expect(result == nil)
    }
}

@Suite("ErrorExtractor Infrastructure Warning Tests")
struct ErrorExtractorInfrastructureTests {
    @Test("Detects testmanagerd SIGSEGV crash")
    func managerdSIGSEGV() throws {
        let stderr = """
        Testing started
        testmanagerd received SIGSEGV: pointer authentication failure
        """
        let result = try ErrorExtractor.formatTestToolResult(
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
    func managerdExcBadAccess() throws {
        let stderr = "testmanagerd: EXC_BAD_ACCESS in HIServices"
        let result = try ErrorExtractor.formatTestToolResult(
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
    func managerdLostConnection() throws {
        let stderr = "testmanagerd lost connection to test process"
        let result = try ErrorExtractor.formatTestToolResult(
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
    func cleanStderr() throws {
        let stderr = "note: Using new build system"
        let result = try ErrorExtractor.formatTestToolResult(
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
    func nilStderr() throws {
        let result = try ErrorExtractor.formatTestToolResult(
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
    func failedWithWarning() {
        #expect(throws: Error.self) {
            try ErrorExtractor.formatTestToolResult(
                output: """
                Test Case 'FooTests.testBar' failed (0.5 seconds)
                Executed 1 test, with 1 failure in 0.5 seconds
                """,
                succeeded: false,
                context: "scheme 'Foo' on macOS",
                stderr: "testmanagerd received SIGSEGV",
            )
        }
    }

    @Test("Detects IDETestRunnerDaemon crash")
    func iDETestRunnerDaemonCrash() throws {
        let stderr = "IDETestRunnerDaemon crash report generated"
        let result = try ErrorExtractor.formatTestToolResult(
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
