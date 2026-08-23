import Testing
import Foundation
import TobaTesting
@testable import XCMCPCore

/// Tests for the child-process discovery that backs reaping the orphaned `lldb-rpc-server` on
/// session teardown (issue vh7-pah).
struct LLDBSessionReapTests {
    @Test
    func `childPIDs finds a forked child process`() async throws {
        // `sh -c 'sleep 30 & wait'` forks `sleep` as a child of `sh`, mirroring how `lldb` spawns
        // `lldb-rpc-server` as a child it must reap on teardown.
        let parent = try TestChildProcess.launch("/bin/sh", ["-c", "sleep 30 & wait"])

        // Wait for sh to fork the sleep child. The child list is the observable signal, so the poll
        // returns the instant the fork lands instead of always paying the worst case.
        await expectEventually("sh forks its child") {
            await !LLDBSession.childPIDs(ofParent: parent.pid).isEmpty
        }

        let children = await LLDBSession.childPIDs(ofParent: parent.pid)
        #expect(!children.isEmpty)

        // Each reported child must be a live, real PID.
        for child in children {
            #expect(child > 0)
            #expect(kill(child, 0) == 0)
        }

        // Killing sh alone orphans the sleep, which then holds this binary's descriptors for the
        // rest of its 30 seconds. Cleanup is awaited rather than deferred, because a deferred async
        // task is not guaranteed to run before the test returns.
        await parent.terminateTree()

        for child in children {
            // The kill is immediate, but the reparenting reaper clears the entry a moment later.
            await expectEventually("child \(child) is reaped") { kill(child, 0) != 0 }
        }
    }

    @Test
    func `childPIDs returns empty for a parent with no children`() async throws {
        // sleep has no children; expect an empty result rather than a spurious match.
        let leaf = try TestChildProcess.launch("/bin/sleep", ["30"])

        let children = await LLDBSession.childPIDs(ofParent: leaf.pid)
        #expect(children.isEmpty)

        await leaf.terminateTree()
    }
}
