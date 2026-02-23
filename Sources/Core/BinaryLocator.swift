import MCP
import Foundation

/// Locates command-line tool binaries on the system.
public enum BinaryLocator: Sendable {
    /// Locates a binary by name, checking Homebrew first then PATH.
    ///
    /// - Parameter name: The binary name (e.g., "swiftformat", "swiftlint").
    /// - Returns: The full path to the binary.
    /// - Throws: ``MCPError/internalError(_:)`` if the binary is not found.
    public static func find(_ name: String) async throws(MCPError) -> String {
        // For swiftformat, prefer Lockwood's version (nicklockwood/SwiftFormat)
        // over Apple's swift-format. Check the Homebrew formula name first.
        if name == "swiftformat" {
            return try await findSwiftFormat()
        }

        return try await locateInPath(name)
    }

    private static func findSwiftFormat() async throws(MCPError) -> String {
        // Homebrew installs Lockwood's swiftformat here
        let homebrewPath = "/opt/homebrew/bin/swiftformat"
        if FileManager.default.fileExists(atPath: homebrewPath) {
            return homebrewPath
        }

        // Check PATH but verify it's Lockwood's version (--version outputs "0.x.y")
        // Apple's swift-format outputs a different format
        if let path = try? await locateViaWhich("swiftformat") {
            if await isLockwoodSwiftFormat(path) {
                return path
            }
        }

        throw .internalError(
            "swiftformat (Lockwood) not found. Install it with: brew install swiftformat",
        )
    }

    /// Returns true if the binary at path is Lockwood's SwiftFormat
    /// (version output is a simple semver like "0.55.5").
    private static func isLockwoodSwiftFormat(_ path: String) async -> Bool {
        guard
            let result = try? await ProcessResult.run(
                path, arguments: ["--version"], mergeStderr: false,
            )
        else { return false }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Lockwood's swiftformat outputs just a version number like "0.55.5"
        // Apple's swift-format outputs something like "swift-format version 600.0.0"
        // or "6.1.0" but from a different binary path
        return !version.contains("swift-format") && version.first?.isNumber == true
    }

    private static func locateInPath(_ name: String) async throws(MCPError) -> String {
        let homebrewPath = "/opt/homebrew/bin/\(name)"
        if FileManager.default.fileExists(atPath: homebrewPath) {
            return homebrewPath
        }

        if let path = try? await locateViaWhich(name) {
            return path
        }

        throw .internalError(
            "\(name) not found. Install it with: brew install \(name)",
        )
    }

    private static func locateViaWhich(_ name: String) async throws -> String? {
        let result = try await ProcessResult.run(
            "/usr/bin/which", arguments: [name], mergeStderr: false,
        )
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !path.isEmpty {
            return path
        }
        return nil
    }
}
