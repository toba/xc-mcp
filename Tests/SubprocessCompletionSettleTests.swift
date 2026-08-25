import MCP
import System
import Testing
import Darwin
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
    func `CPU time the group burns while it is quiet holds the settle off`() async throws {
        // A slow suite writes nothing for minutes behind a 16 KB stdio buffer, and it burns CPU the
        // whole time. The clock alone would kill it. (b5f682b1)
        let cpu = Mutex(Duration.seconds(0))
        let monitor = SettleMonitor(CompletionSettle(grace: .milliseconds(200)) {
            $0.contains("READY")
        }, cpuTime: { cpu.withLock { $0 } })

        monitor.observe("READY\n")
        cpu.withLock { $0 += .seconds(1) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(!monitor.checkSettled(), "the group worked through the quiet period")

        // No further work, so the next quiet period settles.
        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.checkSettled())
    }

    @Test
    func `A group that burns no CPU settles on the grace period`() async throws {
        let monitor = SettleMonitor(CompletionSettle(grace: .milliseconds(200)) {
            $0.contains("READY")
        }, cpuTime: { .seconds(3) })

        monitor.observe("READY\n")
        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.checkSettled())
    }

    @Test
    func `A dead process group settles at once`() async throws {
        let monitor = SettleMonitor(CompletionSettle(grace: .milliseconds(200)) {
            $0.contains("READY")
        }, cpuTime: { nil })

        monitor.observe("READY\n")
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
            "Test Suite 'All tests' passed at 2026-08-25 12:15:00.000.\n"
                + "\t Executed 41 tests, with 0 failures (0 unexpected) in 2.031 (2.044) seconds",
            "Test Suite 'Selected tests' failed at 2026-08-25 12:15:00.000.\n"
                + "\t Executed 1 test, with 1 failure (0 unexpected) in 0.101 (0.102) seconds",
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

    /// XCTest closes every suite with the same summary line, and swift-testing closes every suite
    /// with its own. A run of 2877 tests hit the first one 2836 tests early, which armed the settle
    /// watchdog and killed the run. (b5f682b1)
    @Test
    func `A per-suite summary does not mark the run as finished`() async throws {
        let samples = [
            "Test Suite 'ColumnExpressionTests' passed at 2026-08-25 12:13:55.922.\n"
                + "\t Executed 5 tests, with 0 failures (0 unexpected) in 0.010 (0.011) seconds",
            "Test Suite 'GRDBTests.xctest' passed at 2026-08-25 12:13:55.922.\n"
                + "\t Executed 5 tests, with 0 failures (0 unexpected) in 0.010 (0.011) seconds",
            "\u{2714} Suite \"ColumnExpressionTests\" passed after 0.010 seconds.",
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

/// Verifies the CPU-time probe the settle watchdog reads to tell a working child from a finished
/// one. (b5f682b1)
struct ProcessGroupActivityTests {
    @Test
    func `The probe reports CPU time that grows with work`() async throws {
        let group = getpgrp()
        let first = try #require(ProcessGroupActivity.cpuTime(ofGroup: group))
        var sum = 0
        for value in 0..<5_000_000 { sum = sum &+ value }
        #expect(sum > 0)
        let second = try #require(ProcessGroupActivity.cpuTime(ofGroup: group))
        #expect(second > first)
    }

    @Test
    func `A group id of zero reports nothing`() async throws {
        #expect(ProcessGroupActivity.cpuTime(ofGroup: 0) == nil)
    }
}

/// Verifies what the tool reports when the watchdog ends a run. The counts it parsed cover the
/// output that arrived, so naming them would state a result the run never reported. (b5f682b1)
struct WatchdogTestReportTests {
    /// One suite of a longer run, which is as far as a killed run gets.
    private static let partialOutput = """
        Test Suite 'All tests' started at 2026-08-25 12:10:00.000
        Test Case '-[FooTests testOne]' passed (0.001 seconds).
        Test Suite 'FooTests' passed at 2026-08-25 12:10:01.000.
        \t Executed 40 tests, with 1 failure (0 unexpected) in 0.141 (0.142) seconds
        """

    @Test
    func `A watchdog kill reports no pass or fail count`() async throws {
        var message = ""
        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: Self.partialOutput,
                succeeded: false,
                context: "swift package",
                settledAfterCompletion: true,
            )
            Issue.record("a killed run must not report a result")
        } catch let error as MCPError {
            message = error.localizedDescription
        }
        #expect(message.contains("Test run incomplete"))
        #expect(!message.contains("39 passed"))
        #expect(!message.contains("1 failed"))
        #expect(message.contains("xc-mcp ended the process group"))
    }

    @Test
    func `A run the watchdog left alone still reports its counts`() async throws {
        var message = ""
        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: Self.partialOutput,
                succeeded: false,
                context: "swift package",
            )
            Issue.record("a failing run must throw")
        } catch let error as MCPError {
            message = error.localizedDescription
        }
        #expect(message.contains("Tests failed"))
        #expect(message.contains("39 passed"))
    }
}
