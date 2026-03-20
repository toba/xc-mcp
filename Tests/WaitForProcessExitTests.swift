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

        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .seconds(3))
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

        // Kill it after 300ms from a separate task
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            kill(pid, SIGKILL)
        }

        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .seconds(3))
        #expect(exited, "Should detect process exit after SIGKILL during polling")
    }

    @Test
    func `Timeout is bounded`() async throws {
        // Verify the function returns in reasonable time, not hanging
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        let pid = process.processIdentifier

        let start = ContinuousClock.now
        let exited = await ProcessResult.waitForProcessExit(pid: pid, timeout: .milliseconds(300))
        let elapsed = ContinuousClock.now - start

        #expect(!exited)
        #expect(elapsed < .seconds(2), "Should return near the timeout, not hang")
        #expect(elapsed >= .milliseconds(250), "Should actually wait, not return instantly")

        // Cleanup
        process.terminate()
        process.waitUntilExit()
    }
}
