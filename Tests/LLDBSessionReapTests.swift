import Foundation
import Testing
@testable import XCMCPCore

/// Tests for the child-process discovery that backs reaping the orphaned
/// `lldb-rpc-server` on session teardown (issue vh7-pah).
struct LLDBSessionReapTests {
    @Test
    func `childPIDs finds a forked child process`() async throws {
        // `sh -c 'sleep 30 & wait'` forks `sleep` as a child of `sh`, mirroring how
        // `lldb` spawns `lldb-rpc-server` as a child it must reap on teardown.
        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/bin/sh")
        parent.arguments = ["-c", "sleep 30 & wait"]
        try parent.run()
        defer {
            parent.terminate()
            kill(parent.processIdentifier, SIGKILL)
        }

        // Give sh a moment to fork the sleep child.
        try await Task.sleep(for: .milliseconds(300))

        let children = await LLDBSession.childPIDs(ofParent: parent.processIdentifier)
        #expect(!children.isEmpty)

        // Each reported child must be a live, real PID.
        for child in children {
            #expect(child > 0)
            #expect(kill(child, 0) == 0)
        }
    }

    @Test
    func `childPIDs returns empty for a parent with no children`() async {
        // sleep has no children; expect an empty result rather than a spurious match.
        let leaf = Process()
        leaf.executableURL = URL(fileURLWithPath: "/bin/sleep")
        leaf.arguments = ["30"]
        try? leaf.run()
        defer {
            leaf.terminate()
            kill(leaf.processIdentifier, SIGKILL)
        }

        let children = await LLDBSession.childPIDs(ofParent: leaf.processIdentifier)
        #expect(children.isEmpty)
    }
}
