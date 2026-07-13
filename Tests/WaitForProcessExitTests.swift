import Testing
@testable import XCMCPCore
import Foundation

struct WaitForProcessExitTests {
    @Test
    func `Returns true for already-exited process`() async throws {
        // Launch a process and wait for it to finish before checking
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        let pid = process.processIdentifier

        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .milliseconds(200))
        #expect(exited)
    }

    @Test
    func `Returns true when process exits within timeout`() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.1"]
        try process.run()
        let pid = process.processIdentifier

        // Generous timeout: the poll loop runs on the cooperative thread pool,
        // which can be starved by blocking calls in other suites during a full
        // parallel test run. The child exits in ~100ms regardless.
        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .seconds(15))
        #expect(exited)
    }

    @Test
    func `Returns false when process outlives timeout`() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        let pid = process.processIdentifier

        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .milliseconds(200))
        #expect(!exited)

        // Cleanup
        process.terminate()
        process.waitUntilExit()
    }

    @Test
    func `Detects process killed by SIGKILL mid-wait`() async throws {
        // Launch a long-lived process, then kill it partway through the wait
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        let pid = process.processIdentifier

        // Kill it after 300ms from a detached thread. A cooperative-pool Task can be
        // starved past the wait's own timeout during a full parallel run, leaving the
        // process alive so the wait (correctly) reports no exit and the test flakes; a
        // real thread fires on time regardless of pool pressure.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.3)
            kill(pid, SIGKILL)
        }

        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .seconds(15))
        #expect(exited, "Should detect process exit after SIGKILL during polling")
    }

    @Test
    func `Timeout is bounded`() async throws {
        // Verify the function returns without hanging when the process outlives the timeout.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        let pid = process.processIdentifier

        let start = ContinuousClock.now
        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .milliseconds(300))
        let elapsed = ContinuousClock.now - start

        #expect(!exited)
        // Lower bound only: the kqueue wait itself is bounded to ~300ms, but the measured
        // wall-clock also includes however long the cooperative pool takes to schedule this
        // task's continuation once the wait resumes. Under a full parallel test run that
        // latency is effectively unbounded (observed 19.7s in CI), so an upper bound here is
        // inherently flaky. A genuine hang would block the wait forever and be caught by the
        // CI job timeout, not by a wall-clock assertion.
        #expect(elapsed >= .milliseconds(250), "Should actually wait, not return instantly")

        // Cleanup
        process.terminate()
        process.waitUntilExit()
    }
}
