import AppKit
import Foundation

/// Resolves process IDs from bundle identifiers or app names.
public enum PIDResolver {
    /// Finds the PID of a running app by its bundle identifier.
    ///
    /// Uses `NSRunningApplication` for reliable bundle ID matching, unlike `pgrep`
    /// which searches command-line text and can't match bundle IDs.
    ///
    /// - Parameter bundleId: The app's bundle identifier (e.g., "com.example.MyApp").
    /// - Returns: The PID of the matching process, or `nil` if not found.
    @MainActor
    public static func findPID(forBundleID bundleId: String) -> Int32? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?.processIdentifier
    }

    /// Finds the PID of a running process matching the given pattern.
    ///
    /// Uses `pgrep -f <pattern>` to search command-line text. Returns the first
    /// matching PID. For bundle ID lookups, prefer ``findPID(forBundleID:)`` instead.
    ///
    /// - Parameter pattern: An app name or command-line pattern to search for.
    /// - Returns: The PID of the matching process, or `nil` if not found.
    public static func findPID(matching pattern: String) async -> Int32? {
        guard
            let result = try? await ProcessResult.run(
                "/usr/bin/pgrep", arguments: ["-f", pattern],
            ),
            result.succeeded,
            let pidString = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first,
            let pid = Int32(pidString)
        else {
            return nil
        }
        return pid
    }

    /// Finds the PID of a recently launched app, trying bundle ID first then app name.
    ///
    /// - Parameters:
    ///   - bundleId: The app's bundle identifier (e.g., "com.example.MyApp").
    ///   - appName: The app's name (e.g., "MyApp").
    /// - Returns: The PID of the matching process, or `nil` if not found.
    public static func findLaunchedPID(bundleId: String?, appName: String?) async -> Int32? {
        if let bundleId, let pid = await MainActor.run(body: { findPID(forBundleID: bundleId) }) {
            return pid
        }
        for pattern in [bundleId, appName].compactMap(\.self) {
            if let pid = await findPID(matching: pattern) {
                return pid
            }
        }
        return nil
    }
}
