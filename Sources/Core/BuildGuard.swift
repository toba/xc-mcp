import MCP
import Foundation

/// Prevents concurrent builds of the same project across processes.
/// Uses advisory file locks (`flock`) so separate server processes
/// (xc-build, xc-swift, etc.) coordinate through the filesystem.
/// Non-blocking — throws immediately if another process holds the lock.
public enum BuildGuard {
    /// Try to acquire a cross-process lock for the given project path.
    /// Returns a file descriptor that must be passed to ``release(fd:)``
    /// when the build finishes.
    /// Throws immediately if another process is already building.
    public static func acquire(path: String, description: String) throws(BuildGuardError) -> Int32 {
        let lockFile = lockPath(for: path)
        let fd = open(lockFile, O_CREAT | O_WRONLY, 0o644)
        guard fd >= 0 else {
            throw BuildGuardError(path: path)
        }
        // Non-blocking exclusive lock
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw BuildGuardError(path: path)
        }
        // Write description so other processes can see what holds the lock
        let data = Data(description.utf8)
        _ = ftruncate(fd, 0)
        _ = data.withUnsafeBytes { pwrite(fd, $0.baseAddress!, $0.count, 0) }
        return fd
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

    public var description: String {
        "Another process is already building this project (\(path)). Wait for it to finish before starting another build."
    }

    public func toMCPError() -> MCPError {
        .invalidRequest(description)
    }
}
