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

    /// Regression test for t57-a7q.
    ///
    /// Prior to the fix, a `readUntilPrompt` timeout left the GCD reader thread blocked in
    /// `FileHandle.availableData` past the function's return — so when the next caller spawned
    /// its own reader, the leaked reader would steal the next command's bytes the moment they
    /// arrived, then exit on its stale `finished` flag and discard them. The next caller's
    /// reader was left with no data until its own timeout fired.
    ///
    /// Symptoms: a "(no output received)" timeout on the very first user command after a
    /// no-op drain that timed out (e.g. `drainPendingOutput` / `checkForEarlyCrash`).
    /// Regression test for t57-a7q.
    ///
    /// `drainPendingOutput` / `checkForEarlyCrash` issue tolerated `readUntilPrompt` calls with
    /// `poisonOnFailure: false`. Before the fix, those timeouts left the GCD reader thread
    /// blocked in `FileHandle.availableData` past the function's return — so the very next
    /// `sendCommand`'s reader raced the leaked one for bytes on the shared PTY fd. The leaked
    /// reader could consume the response and discard it on its stale `finished` check,
    /// leaving the new reader to time out with "no output received".
    ///
    /// This test triggers a tolerated timeout against an idle session and verifies the next
    /// command's response arrives correlated to its caller, not silently swallowed.
    @Test
    func `a tolerated short timeout does not leak the reader and the next command succeeds`() async throws {
        try #require(Self.lldbAvailable, "lldb not installed")

        // Generous per-command timeout absorbs cooperative-pool starvation in the full parallel
        // test run on CI; the leak-detection signal is "did the next sendCommand return", not
        // "how fast did it return".
        let session = try LLDBSession(pid: 0, commandTimeout: 30)
        defer { Task { await session.terminate() } }
        _ = try await session.readUntilPrompt()

        // Simulate `drainPendingOutput`'s tight, non-poisoning read against an idle PTY — no
        // command was sent, so no prompt will arrive, and the read must time out cleanly. With
        // the fix the GCD reader is fully torn down before the continuation resumes; before
        // the fix it stayed blocked in `availableData` until the next command's bytes arrived.
        await #expect(throws: LLDBError.self) {
            _ = try await session.readUntilPrompt(timeout: 0.2, poisonOnFailure: false)
        }

        // The session must remain usable: `poisonOnFailure: false` callers expect the next
        // `sendCommand` to behave normally and the response to be correlated to *this* call.
        // A leaked reader would silently swallow the response and force this call to time out
        // against the session's full commandTimeout (30s), so a wide-but-bounded budget still
        // catches the regression without flaking on a loaded CI runner.
        let start = ContinuousClock.now
        let output = try await session.sendCommand("version")
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < .seconds(15), "next sendCommand took \(elapsed) — reader likely leaked")
        #expect(output.contains("lldb"), "expected version output, got: \(output)")

        let poisoned = await session.isPoisoned
        #expect(!poisoned, "tolerated drain timeout must not poison the session")
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
