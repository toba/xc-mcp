import Testing
@testable import XCMCPCore
import Foundation
import Subprocess
import System

/// Verifies the wall-clock `timeout` backstop reliably terminates a subprocess
/// tree — including grandchildren that hold the stdout/stderr pipes open — rather
/// than hanging until the caller cancels manually. (ycq-rdc)
struct SubprocessTimeoutGroupKillTests {
    @Test
    func `Timeout terminates a parent that ignores SIGTERM`() async throws {
        let start = ContinuousClock.now
        await #expect(throws: ProcessError.self) {
            // sh traps and ignores SIGTERM, so Subprocess's graceful-shutdown
            // teardown can't stop it — only a SIGKILL of the process group does.
            // The inner sleep is effectively unbounded (600s) so the only way this
            // returns is the timeout backstop firing — never the command exiting on
            // its own — which keeps the wall-clock assertion below meaningful.
            _ = try await ProcessResult.runSubprocess(
                .path(FilePath("/bin/sh")),
                arguments: ["-c", "trap '' TERM; sleep 600"],
                timeout: .seconds(1),
            )
        }
        // The backstop fires in ~1s locally. The 60s bound only guards against a true
        // hang (the command would otherwise run 600s); it is deliberately generous
        // because the saturated CI runner (1200+ parallel tests) can starve the
        // cooperative pool and delay the kill+drain by tens of seconds. (ycq-rdc)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(60), "Timeout backstop must fire, not hang")
    }

    @Test
    func `Timeout reaps a grandchild holding the pipe open`() async throws {
        let start = ContinuousClock.now
        await #expect(throws: ProcessError.self) {
            // The parent shell ignores SIGTERM and waits on a backgrounded child
            // that inherits (and holds open) the stdout/stderr pipes. Killing only
            // the parent leaves the child alive, the pipes never see EOF, and output
            // collection hangs forever. The group SIGKILL is what unblocks it.
            _ = try await ProcessResult.runSubprocess(
                .path(FilePath("/bin/sh")),
                arguments: ["-c", "trap '' TERM; sleep 600 & wait"],
                timeout: .seconds(1),
            )
        }
        // Generous bound for the same reason as above: the group SIGKILL reaps the
        // grandchild in ~1s locally, but CI starvation can defer the post-kill drain.
        // A failure to reap would hang indefinitely (the pipe never sees EOF), so any
        // return well under the 600s command lifetime proves the reap worked. (ycq-rdc)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(60), "Group kill must reap the grandchild, not hang")
    }

    @Test
    func `Fast command completes normally despite a generous timeout`() async throws {
        let result = try await ProcessResult.runSubprocess(
            .path(FilePath("/bin/echo")),
            arguments: ["hello"],
            timeout: .seconds(30),
        )
        #expect(result.succeeded)
        #expect(result.stdout.contains("hello"))
    }
}
