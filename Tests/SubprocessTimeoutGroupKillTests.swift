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
            _ = try await ProcessResult.runSubprocess(
                .path(FilePath("/bin/sh")),
                arguments: ["-c", "trap '' TERM; sleep 60"],
                timeout: .seconds(1),
            )
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(20), "Timeout backstop must fire, not hang")
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
                arguments: ["-c", "trap '' TERM; sleep 60 & wait"],
                timeout: .seconds(1),
            )
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(20), "Group kill must reap the grandchild, not hang")
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
