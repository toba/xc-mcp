import Foundation
import Testing

@testable import XCMCPCore

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
      if case .text(let t) = $0 { return t }
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
      if case .text(let t) = $0 { return t }
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
      if case .text(let t) = $0 { return t }
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
      if case .text(let t) = $0 { return t }
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
      if case .text(let t) = $0 { return t }
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
      if case .text(let t) = $0 { return t }
      return nil
    }.joined()
    #expect(text.contains("Warning: The test runner daemon crashed"))
  }
}
