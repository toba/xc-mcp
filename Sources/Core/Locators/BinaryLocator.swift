import MCP
import Foundation

/// Locates command-line tool binaries on the system.
public enum BinaryLocator: Sendable {
    /// Locates a binary by name, checking Homebrew first then PATH.
    ///
    /// - Parameter name: The binary name (e.g., "sm", "xcbeautify").
    /// - Returns: The full path to the binary.
    /// - Throws: ``MCPError/internalError(_:)`` if the binary is not found.
    public static func find(_ name: String) async throws(MCPError) -> String {
        let homebrewPath = "/opt/homebrew/bin/\(name)"
        if FileManager.default.fileExists(atPath: homebrewPath) { return homebrewPath }

        if let path = try? await locateViaWhich(name) { return path }

        throw .internalError("\(name) not found. Install it with: brew install \(name)")
    }

    private static func locateViaWhich(_ name: String) async throws -> String? {
        let result = try await ProcessResult.run(
            "/usr/bin/which", arguments: [name], mergeStderr: false,
        )
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !path.isEmpty { return path }
        return nil
    }
}
