import Foundation

/// Shared date formatters for tool output
///
/// A formatter is expensive to build, and several tools rebuilt the same one per call. Each
/// formatter here is configured once at initialization and never mutated afterwards, which is the
/// condition under which Foundation permits concurrent reads.
public enum TimestampFormatting {
    /// `yyyy-MM-dd HH:mm:ss` in the local time zone, the form the build-log tools print
    public static nonisolated(unsafe) let buildLog: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Internet date and time, for example `2026-08-25T05:19:53Z`
    public static nonisolated(unsafe) let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
