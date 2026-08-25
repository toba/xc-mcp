import MCP
import Foundation

/// One `.xcactivitylog` file Xcode wrote under a DerivedData root
public struct BuildLogEntry: Sendable {
    public let path: String
    public let date: Date

    public init(path: String, date: Date) {
        self.path = path
        self.date = date
    }

    /// The modification date rendered the way the build tools print it.
    public var formattedDate: String { TimestampFormatting.buildLog.string(from: date) }
}

/// Finds and decompresses the `.xcactivitylog` files under a DerivedData root
///
/// Xcode writes one gzipped log per build under `Logs/Build`. A build that dies before it writes
/// anything leaves a zero-byte file behind, so an empty log is skipped. It decompresses to nothing
/// and a caller that picks it reports no errors from a build that failed.
public enum BuildLogLocator {
    /// The directory Xcode writes build logs to.
    ///
    /// - Parameter projectRoot: The DerivedData root for the project, from ``DerivedDataLocator``.
    public static func logsDirectory(inProjectRoot projectRoot: String) -> String {
        URL(fileURLWithPath: projectRoot).appendingPathComponent("Logs/Build").path
    }

    /// The non-empty build logs, newest first.
    ///
    /// - Parameters:
    ///   - projectRoot: The DerivedData root for the project.
    ///   - limit: The most logs to return. `nil` returns every one.
    /// - Returns: The logs, empty when the directory holds none or cannot be read.
    public static func logs(
        inProjectRoot projectRoot: String,
        limit: Int? = nil,
    ) -> [BuildLogEntry] {
        let logsDir = logsDirectory(inProjectRoot: projectRoot)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: logsDir) else { return [] }

        let sorted = entries.filter { $0.hasSuffix(".xcactivitylog") }
            .compactMap { name -> BuildLogEntry? in
                let path = URL(fileURLWithPath: logsDir).appendingPathComponent(name).path
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let date = attrs[.modificationDate] as? Date,
                      let size = attrs[.size] as? UInt64,
                      size > 0 else { return nil }
                return BuildLogEntry(path: path, date: date)
            }
            .sorted { $0.date > $1.date }

        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    /// The non-empty build logs, newest first, rejecting the case where there are none.
    ///
    /// - Parameters:
    ///   - projectRoot: The DerivedData root for the project.
    ///   - limit: The most logs to return. `nil` returns every one.
    /// - Throws: ``MCPError/internalError(_:)`` when the directory holds no usable log.
    public static func requireLogs(
        inProjectRoot projectRoot: String,
        limit: Int? = nil,
    ) throws(MCPError) -> [BuildLogEntry] {
        let found = logs(inProjectRoot: projectRoot, limit: limit)
        guard !found.isEmpty else {
            throw .internalError(
                "No non-empty build logs found in \(logsDirectory(inProjectRoot: projectRoot))",
            )
        }
        return found
    }

    /// The newest non-empty build log.
    ///
    /// - Parameter projectRoot: The DerivedData root for the project.
    /// - Throws: ``MCPError/internalError(_:)`` when the directory holds no usable log.
    public static func newestLog(
        inProjectRoot projectRoot: String
    ) throws(MCPError) -> BuildLogEntry { try requireLogs(inProjectRoot: projectRoot, limit: 1)[0] }

    /// Decompresses one log to text.
    ///
    /// - Parameter log: The log to read.
    /// - Returns: The log body, which runs to several megabytes for a large build.
    public static func decompress(_ log: BuildLogEntry) async throws -> String {
        let result = try await ProcessResult.run(
            "/usr/bin/gunzip", arguments: ["-c", log.path], timeout: gunzipTimeout,
        )
        return result.stdout
    }

    /// The budget one gunzip call gets.
    public static let gunzipTimeout: Duration = .seconds(30)
}
