import Foundation
import Testing
@testable import XCMCPCore

struct TestCrashDiagnosticsTests {
    // MARK: - detectCrash

    @Test
    func `Detect bare signal trap`() {
        #expect(TestCrashDiagnostics.detectCrash(in: "Test crashed with signal trap."))
    }

    @Test
    func `Detect restart-after-crash banner`() {
        #expect(
            TestCrashDiagnostics.detectCrash(
                in: "Restarting after unexpected exit, crash, or test timeout",
            ),
        )
    }

    @Test
    func `Ordinary assertion failure is not a crash`() {
        let output = """
        Test Case '-[MyTests testThing]' failed (0.1 seconds).
          ✗ testThing — XCTAssertEqual failed: ("1") is not equal to ("2")
        """
        #expect(!TestCrashDiagnostics.detectCrash(in: output))
    }

    // MARK: - extractTrapLines

    @Test
    func `Extract Swift fatal error line`() {
        let stderr = """
        Some noise here
        DOM/Document+changes.swift:119: Fatal error: Dropped 1 text element change(s); text view may be stale
        more noise
        """
        let lines = TestCrashDiagnostics.extractTrapLines(from: stderr)
        #expect(lines.count == 1)
        #expect(lines[0].contains("Fatal error: Dropped 1 text element change"))
    }

    @Test
    func `Extract precondition and exception lines`() {
        let stderr = """
        Precondition failed: index out of range
        *** Terminating app due to uncaught exception 'NSRangeException', reason: 'Out of bounds'
        """
        let lines = TestCrashDiagnostics.extractTrapLines(from: stderr)
        #expect(lines.count == 2)
    }

    @Test
    func `Trap line extraction de-duplicates`() {
        let stderr = """
        Fatal error: boom
        Fatal error: boom
        """
        #expect(TestCrashDiagnostics.extractTrapLines(from: stderr).count == 1)
    }

    @Test
    func `No trap lines in clean stderr`() {
        #expect(TestCrashDiagnostics.extractTrapLines(from: "all good\nnothing here").isEmpty)
    }

    // MARK: - predicate / timestamp

    @Test
    func `Fatal log predicate without process is content-only`() {
        let predicate = TestCrashDiagnostics.fatalLogPredicate(processName: nil)
        #expect(predicate.contains("Fatal error"))
        #expect(!predicate.contains("process =="))
    }

    @Test
    func `Fatal log predicate scopes to process`() {
        let predicate = TestCrashDiagnostics.fatalLogPredicate(processName: "ThesisTests")
        #expect(predicate.hasPrefix("process == \"ThesisTests\""))
        #expect(predicate.contains("Fatal error"))
    }

    @Test
    func `Log timestamp uses log show format`() {
        let date = Date(timeIntervalSince1970: 0)
        let stamp = TestCrashDiagnostics.logTimestamp(date)
        // 1970-01-01 in some local zone — assert the shape, not the value.
        #expect(stamp.count == 19)
        #expect(stamp.contains("-"))
        #expect(stamp.contains(":"))
    }

    // MARK: - diagnose

    @Test
    func `Diagnose surfaces stderr trap without log window`() async {
        let stderr = "Foo.swift:1: Fatal error: kaboom"
        let diagnosis = await TestCrashDiagnostics.diagnose(stderr: stderr)
        #expect(diagnosis != nil)
        #expect(diagnosis?.contains("Crash diagnosis") == true)
        #expect(diagnosis?.contains("kaboom") == true)
    }

    @Test
    func `Diagnose returns nil with no evidence and no window`() async {
        let diagnosis = await TestCrashDiagnostics.diagnose(stderr: "nothing useful")
        #expect(diagnosis == nil)
    }
}
