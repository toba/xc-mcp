import AppKit
import Foundation

/// Resolves process IDs from bundle identifiers or app names.
public enum PIDResolver {
    /// Finds the PID of a running app by its bundle identifier.
    ///
    /// Uses `NSRunningApplication` for reliable bundle ID matching, unlike `pgrep` which searches
    /// command-line text and can't match bundle IDs.
    ///
    /// - Parameter bundleID: The app's bundle identifier (e.g., "com.example.MyApp").
    /// - Returns: The PID of the matching process, or `nil` if not found.
    @MainActor
    public static func findPID(forBundleID bundleID: String) -> Int32? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.processIdentifier
    }

    /// Finds the PIDs of running apps whose name exactly matches `name`.
    ///
    /// Matches the app's localized name, executable basename, or bundle name (minus the `.app`
    /// extension) via exact equality — never a substring or command-line search. This avoids the
    /// `pkill -f` footgun where an unrelated process carrying the name anywhere in its arguments
    /// would be selected (and killed).
    ///
    /// - Parameter name: The app's display or executable name (e.g., "MyApp").
    /// - Returns: The PIDs of all matching running apps (empty if none).
    @MainActor
    public static func findPIDs(forAppName name: String) -> [Int32] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            appNameMatches(
                name,
                localizedName: app.localizedName,
                executableName: app.executableURL?.lastPathComponent,
                bundleName: app.bundleURL?.deletingPathExtension().lastPathComponent,
            ) ? app.processIdentifier : nil
        }
    }

    /// Exact-match predicate for resolving an app name against a running application's identifiers.
    ///
    /// Extracted as a pure function so the matching contract (exact equality, never substring) is
    /// unit-testable without launching real apps.
    static func appNameMatches(
        _ name: String,
        localizedName: String?,
        executableName: String?,
        bundleName: String?,
    ) -> Bool {
        name == localizedName || name == executableName || name == bundleName
    }

    /// Finds the PID of a running process matching the given pattern.
    ///
    /// Uses `pgrep -f <pattern>` to search command-line text. Returns the first matching PID. For
    /// bundle ID lookups, prefer ``findPID(forBundleID:)`` instead.
    ///
    /// - Parameter pattern: An app name or command-line pattern to search for.
    /// - Returns: The PID of the matching process, or `nil` if not found.
    public static func findPID(matching pattern: String) async -> Int32? {
        guard let result = try? await ProcessResult.run(
            "/usr/bin/pgrep", arguments: ["-f", pattern]),
              result.succeeded,
              let pidString = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                  .components(separatedBy: .newlines).first,
              let pid = Int32(pidString) else { return nil }
        return pid
    }

    /// Finds the PID of a recently launched app, trying bundle ID first then app name.
    ///
    /// - Parameters:
    ///   - bundleID: The app's bundle identifier (e.g., "com.example.MyApp").
    ///   - appName: The app's name (e.g., "MyApp").
    /// - Returns: The PID of the matching process, or `nil` if not found.
    public static func findLaunchedPID(bundleID: String?, appName: String?) async -> Int32? {
        if let bundleID, let pid = await findPID(forBundleID: bundleID) { return pid }
        for pattern in [bundleID, appName].compactMap(\.self) {
            if let pid = await findPID(matching: pattern) { return pid }
        }
        return nil
    }
}
