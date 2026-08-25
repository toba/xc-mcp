import Foundation

/// One snapshot of the process environment, shared by every default argument that needs it
///
/// `ProcessInfo.processInfo.environment` materializes the whole environment on each read, so a
/// function that defaults a parameter to it pays that cost at every call site. This snapshot is
/// taken once. A caller that must observe a later `setenv` reads `ProcessInfo` directly instead.
public enum ProcessEnvironment {
    public static let current: [String: String] = ProcessInfo.processInfo.environment
}
