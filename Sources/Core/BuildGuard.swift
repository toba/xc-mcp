import MCP
import Foundation

/// Prevents concurrent builds of the same project across processes.
/// Uses advisory file locks (`flock`) so separate server processes
/// (xc-build, xc-swift, etc.) coordinate through the filesystem.
/// Blocks until the lock is acquired or the timeout expires.
public enum BuildGuard {
    public static let defaultTimeout: Duration = .seconds(300)
    private static let pollInterval: Duration = .milliseconds(500)

    /// Acquire a cross-process lock for the given project path.
    /// Returns a file descriptor that must be passed to ``release(fd:)``
    /// when the build finishes.
    /// Waits up to `timeout` (default 5 minutes) for the lock to become available.
    public static func acquire(
        path: String, description: String,
        timeout: Duration = defaultTimeout,
    ) async throws(BuildGuardError) -> Int32 {
        let lockFile = lockPath(for: path)
        let fd = open(lockFile, O_CREAT | O_WRONLY, 0o644)
        guard fd >= 0 else {
            throw BuildGuardError(path: path, timedOut: false)
        }
        // Try non-blocking first — fast path when no contention
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            writeLockDescription(fd: fd, description: description)
            return fd
        }
        // Poll until the lock is acquired or timeout expires
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                close(fd)
                throw BuildGuardError(path: path, timedOut: false)
            }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                writeLockDescription(fd: fd, description: description)
                return fd
            }
        }
        close(fd)
        throw BuildGuardError(path: path, timedOut: true)
    }

    private static func writeLockDescription(fd: Int32, description: String) {
        let data = Data(description.utf8)
        _ = ftruncate(fd, 0)
        _ = data.withUnsafeBytes { pwrite(fd, $0.baseAddress!, $0.count, 0) }
    }

    /// Release the build lock.
    public static func release(fd: Int32) {
        flock(fd, LOCK_UN)
        close(fd)
    }

    private static func lockPath(for projectPath: String) -> String {
        let hash = projectPath.utf8.reduce(into: UInt64(5381)) { h, c in
            h = h &* 33 &+ UInt64(c)
        }
        return "/tmp/xc-mcp-build-\(hash).lock"
    }
}

public struct BuildGuardError: Error, CustomStringConvertible, MCPErrorConvertible {
    public let path: String
    public let timedOut: Bool

    public var description: String {
        if timedOut {
            return "Timed out waiting for build lock on \(path). Another process has been building this project for over 5 minutes."
        }
        return "Failed to acquire build lock for \(path)."
    }

    public func toMCPError() -> MCPError {
        .invalidRequest(description)
    }
}
