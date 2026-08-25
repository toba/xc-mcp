import Testing
import Foundation
@testable import XCMCPCore

/// Tests for the cross-process build lock.
struct BuildGuardTests {
    /// A project path unique to each test so no two runs contend for the same lock file.
    private static func uniqueProjectPath(_ label: String) -> String {
        "/tmp/xc-mcp-build-guard-test-\(label)-\(ProcessInfo.processInfo.processIdentifier)"
    }

    /// An empty description used to trap: `Data` reports a nil `baseAddress` for zero bytes, and
    /// the write path force-unwrapped it.
    @Test
    func `an empty lock description acquires the lock instead of trapping`() async throws {
        let path = Self.uniqueProjectPath("empty-description")
        let fd = try await BuildGuard.acquire(path: path, description: "")
        defer { BuildGuard.release(fd: fd) }
        #expect(fd >= 0)
    }

    @Test
    func `a non-empty lock description lands in the lock file`() async throws {
        let path = Self.uniqueProjectPath("described")
        let fd = try await BuildGuard.acquire(path: path, description: "build Thesis")
        defer { BuildGuard.release(fd: fd) }

        let lockFile = BuildGuard.lockPath(for: path)
        let written = try String(contentsOfFile: lockFile, encoding: .utf8)
        #expect(written == "build Thesis")
    }
}
