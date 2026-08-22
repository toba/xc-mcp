import System
import Testing
import Foundation
import Subprocess
import Synchronization
@testable import XCMCPCore

/// Verifies the settle bookkeeping on its own, with no subprocess in the way. A failure here
/// localizes the fault to the marker or the grace period rather than to the process plumbing.
/// (74fa1d59)
struct SettleMonitorTests {
    @Test
    func `The monitor settles only after the marker and the grace period`() async throws {
        let monitor = SettleMonitor(CompletionSettle(grace: .milliseconds(200)) {
            $0.contains("READY")
        })
        #expect(!monitor.checkSettled(), "no output yet")

        monitor.observe("working\n")
        try await Task.sleep(for: .milliseconds(400))
        #expect(!monitor.checkSettled(), "the marker never appeared")

        monitor.observe("READY\n")
        #expect(!monitor.checkSettled(), "the grace period has not elapsed")

        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.checkSettled())
    }

    @Test
    func `Output after the marker restarts the grace period`() async throws {
        let monitor = SettleMonitor(CompletionSettle(grace: .milliseconds(300)) {
            $0.contains("READY")
        })
        monitor.observe("READY\n")
        try await Task.sleep(for: .milliseconds(200))
        monitor.observe("one more line\n")
        try await Task.sleep(for: .milliseconds(200))
        #expect(!monitor.checkSettled(), "the later output restarts the clock")

        try await Task.sleep(for: .milliseconds(250))
        #expect(monitor.checkSettled())
    }

    @Test
    func `A marker split across two chunks still settles`() async throws {
        let monitor = SettleMonitor(CompletionSettle(grace: .milliseconds(200)) {
            $0.contains("READY")
        })
        monitor.observe("REA")
        monitor.observe("DY\n")
        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.checkSettled())
    }

    @Test
    func `The monitor reports the kill the watchdog made`() async throws {
        let monitor = SettleMonitor(CompletionSettle { $0.contains("READY") })
        #expect(!monitor.didSettle)
        monitor.markSettled()
        #expect(monitor.didSettle)
    }

    @Test
    func `The watchdog calls back once the monitor settles`() async throws {
        let monitor = SettleMonitor(CompletionSettle(grace: .milliseconds(200)) {
            $0.contains("READY")
        })
        let killed = Mutex(false)
        monitor.observe("READY\n")
        // The stand-in run ends when the callback fires, the way a real subprocess ends when the
        // kill lets its pipes close. It stands in for the subprocess so a failure here belongs to
        // the watchdog alone.
        let value = try await ProcessResult.watchForSettle(monitor) {
            while !killed.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(50)) }
            return 7
        } onSettle: {
            killed.withLock { $0 = true }
        }
        #expect(value == 7)
        #expect(killed.withLock { $0 })
        #expect(monitor.didSettle)
        #expect(monitor.pollCount > 0, "the watchdog never polled the monitor")
    }
}

/// Verifies the completion-settle backstop: a child that finishes its work and then stops exiting
/// must not hold the tool open. `swift-test` reads the test binary's output pipe, so a process the
/// tests spawned that inherited that pipe keeps the read blocked long after the results are
/// complete. (74fa1d59)
struct SubprocessCompletionSettleTests {
    /// A marker predicate that matches the literal the test commands print.
    private static let readySettle = CompletionSettle(grace: .seconds(1)) { $0.contains("READY") }

    @Test
    func `Settle ends a run whose orphan holds the pipe open`() async throws {
        let start = ContinuousClock.now
        // The shell backgrounds a sleep that inherits stdout, prints the marker, then waits. Output
        // collection cannot see EOF until the sleep dies, which is the shape of the `swift-test`
        // hang: a live parent blocked on a pipe its orphan holds open. Only the settle kill
        // unblocks it. The shell must stay alive, because Subprocess stops collecting once its
        // direct child is reaped.
        let result = try await ProcessResult.runSubprocess(
            .path(FilePath("/bin/sh")),
            arguments: ["-c", "sleep 30 & echo READY; wait"],
            mergeStderr: true,
            settle: Self.readySettle,
        )
        // The settle fires ~1.5s in. The bound is generous because a saturated runner can defer the
        // kill and the drain, and any return well under the 30s command lifetime proves the
        // backstop worked.
        let elapsed = ContinuousClock.now - start
        #expect(result.settledAfterCompletion)
        #expect(elapsed < .seconds(20), "Settle must end the run, not wait for the orphan")
        #expect(result.stdout.contains("READY"))
    }

    @Test
    func `Settle leaves a quiet run alone until its marker appears`() async throws {
        // No output ever matches the marker, so the watchdog must never fire even though the
        // command outlives the grace period.
        let result = try await ProcessResult.runSubprocess(
            .path(FilePath("/bin/sh")),
            arguments: ["-c", "sleep 3; echo done"],
            mergeStderr: true,
            settle: Self.readySettle,
        )
        #expect(!result.settledAfterCompletion)
        #expect(result.succeeded)
        #expect(result.stdout.contains("done"))
    }

    @Test
    func `A clean exit after the marker reports no settle`() async throws {
        let result = try await ProcessResult.runSubprocess(
            .path(FilePath("/bin/echo")),
            arguments: ["READY"],
            mergeStderr: true,
            settle: Self.readySettle,
        )
        #expect(!result.settledAfterCompletion)
        #expect(result.succeeded)
        #expect(result.termination == .exited(0))
    }

    @Test
    func `A signalled child reports the signal, not an exit status`() async throws {
        let result = try await ProcessResult.runSubprocess(
            .path(FilePath("/bin/sh")),
            arguments: ["-c", "kill -9 $$"],
            mergeStderr: true,
        )
        #expect(result.termination == .signaled(SIGKILL))
        #expect(!result.succeeded)
        #expect(result.termination.isAbnormal)
        #expect(result.termination.description.contains("signal 9"))
    }

    @Test
    func `A non-zero exit reports its status and is not abnormal`() async throws {
        let result = try await ProcessResult.runSubprocess(
            .path(FilePath("/bin/sh")),
            arguments: ["-c", "exit 3"],
            mergeStderr: true,
        )
        #expect(result.termination == .exited(3))
        #expect(result.exitCode == 3)
        #expect(!result.termination.isAbnormal)
        #expect(result.termination.description == "exit status 3")
    }
}

/// Verifies the completion marker the `swift test` settle policy uses. (74fa1d59)
///
/// Every sample line lives inside a test body rather than in `@Test(arguments:)`. Swift Testing
/// echoes an argument into the run output, and this suite's samples are test summaries, so an
/// argument would land in xc-mcp's own parsed results as a phantom failure.
struct TestRunFinishedMarkerTests {
    @Test
    func `A summary line marks the run as finished`() async throws {
        let samples = [
            "\u{25c7} Test run started.\n\u{2714} Test run with 1731 tests in 210 suites"
                + " passed after 28.513 seconds.",
            "\u{2718} Test run with 4 tests failed, 12 tests passed after 3.100 seconds.",
            "Test run with 2 tests in 1 suite failed after 1.200 seconds with 2 issues.",
            "Executed 41 tests, with 0 failures (0 unexpected) in 2.031 (2.044) seconds",
            "     Executed 1 test, with 1 failure (0 unexpected) in 0.101 (0.102) seconds",
        ]
        for (index, sample) in samples.enumerated() {
            #expect(ErrorExtractor.indicatesTestRunFinished(sample), "sample \(index)")
        }
    }

    @Test
    func `Ordinary progress output does not mark the run as finished`() async throws {
        let samples = [
            "Test Suite 'All tests' started at 2026-08-22 05:00:00.000",
            "Test Case '-[FooTests testBar]' passed (0.001 seconds).",
            "\u{25c7} Test \"builds a package\" started.",
            "Building for debugging...\n[42/128] Compiling XCMCPCore ProcessResult.swift",
            "",
        ]
        for (index, sample) in samples.enumerated() {
            #expect(!ErrorExtractor.indicatesTestRunFinished(sample), "sample \(index)")
        }
    }

    @Test
    func `A marker split across two chunks matches once the tail holds both halves`() async throws {
        let first = "\u{2714} Test run with 1731 tests in 210 suites"
        #expect(!ErrorExtractor.indicatesTestRunFinished(first))
        #expect(ErrorExtractor.indicatesTestRunFinished(first + " passed after 28.513 seconds."))
    }
}
