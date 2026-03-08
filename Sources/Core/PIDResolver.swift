import Foundation

/// Resolves process IDs from bundle identifiers or app names via `pgrep`.
public enum PIDResolver {
    /// Finds the PID of a running process matching the given pattern.
    ///
    /// Uses `pgrep -f <pattern>` to search. Returns the first matching PID.
    ///
    /// - Parameter pattern: A bundle identifier or app name to search for.
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
        for pattern in [bundleId, appName].compactMap(\.self) {
            if let pid = await findPID(matching: pattern) {
                return pid
            }
        }
        return nil
    }
}
