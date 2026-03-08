import MCP

/// Prevents concurrent builds of the same project. Keyed by project path,
/// so different projects can build simultaneously. When a build is already
/// running for a given path, subsequent attempts get an immediate friendly
/// error — no blocking, no waiting.
public actor BuildGuard {
    public static let shared = BuildGuard()

    private var active: [String: String] = [:] // path → description

    /// Try to start a build for a project path. Throws immediately if that
    /// project is already being built.
    public func acquire(path: String, description: String) throws(BuildGuardError) {
        if let existing = active[path] {
            throw BuildGuardError(active: existing, path: path)
        }
        active[path] = description
    }

    /// Release the build slot for a project path.
    public func release(path: String) {
        active[path] = nil
    }
}

public struct BuildGuardError: Error, CustomStringConvertible, MCPErrorConvertible {
    public let active: String
    public let path: String

    public var description: String {
        "Another agent is already building this project (\(active)). Wait for it to finish before starting another build."
    }

    public func toMCPError() -> MCPError {
        .invalidRequest(description)
    }
}
