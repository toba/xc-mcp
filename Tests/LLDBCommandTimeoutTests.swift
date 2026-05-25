import Foundation
import Testing
@testable import XCMCPCore

/// Tests for the interactive per-command timeout that prevents inspection commands from appearing
/// to hang for the full launch/`--waitfor` window when a read wedges (issue gpw-mi6).
struct LLDBCommandTimeoutTests {
    /// Path to the system `lldb`; tests are skipped when it isn't installed (e.g. minimal CI).
    private static var lldbAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/lldb")
    }

    @Test
    func `interactive timeout is far below the launch window`() {
        // The launch/waitfor sessions use a 120s window; the interactive timeout must be much
        // smaller so a wedged inspection fails fast instead of hanging for two minutes.
        #expect(LLDBSession.interactiveCommandTimeout > 0)
        #expect(LLDBSession.interactiveCommandTimeout <= 60)
    }

    @Test
    func `a wedged command times out within the lowered window and poisons the session`() async throws {
        try #require(Self.lldbAvailable, "lldb not installed")

        // Start LLDB with a generous launch-style window, then lower it to interactive, mirroring
        // what createLaunchSession/createOpenAndAttachSession do once attach completes.
        let session = try LLDBSession(pid: 0, commandTimeout: 120)
        defer { Task { await session.terminate() } }
        _ = try await session.readUntilPrompt()
        await session.setCommandTimeout(2)

        // `script ...sleep` blocks LLDB's command interpreter so no prompt returns — the same shape
        // as a wedged inspection at a breakpoint. It must time out at ~2s, not the 120s window.
        let start = ContinuousClock.now
        await #expect(throws: LLDBError.self) {
            _ = try await session.sendCommand("script import time; time.sleep(30)")
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(15))

        // A timed-out read poisons the session so the manager recreates it on next use.
        let poisoned = await session.isPoisoned
        #expect(poisoned)
    }

    @Test
    func `a flood of output aborts within the byte cap instead of running to the timeout`() async throws {
        try #require(Self.lldbAvailable, "lldb not installed")

        // A long timeout proves the abort is driven by the byte cap, not the time cap: a hot
        // breakpoint floods the PTY faster than a prompt ever returns, and the reader must bail on
        // the byte budget rather than spin until the (here, very long) timeout.
        let session = try LLDBSession(pid: 0, commandTimeout: 600)
        defer { Task { await session.terminate() } }
        _ = try await session.readUntilPrompt()

        // Emit well over the 1 MB cap with no intervening prompt, mimicking breakpoint chatter.
        let start = ContinuousClock.now
        await #expect(throws: LLDBError.self) {
            _ = try await session.sendCommand(
                "script import sys; [sys.stdout.write('x' * 100 + chr(10)) for _ in range(40000)]",
            )
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(60))

        // The flood wedges the session just like a timeout, so it must be poisoned for recreation.
        let poisoned = await session.isPoisoned
        #expect(poisoned)
    }
}
