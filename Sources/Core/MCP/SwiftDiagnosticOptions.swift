import MCP
import Foundation

/// The JSON-schema properties every Swift package tool declares the same way.
///
/// The description text is part of the tool's contract with the client, so seven copies of it drift
/// the moment one is edited.
public enum SwiftPackageToolSchema {
    /// The `package_path` property every Swift package tool accepts.
    public static let packagePath: [String: Value] = [
        "package_path": .object([
            "type": .string("string"),
            "description": .string(
                "Path to the Swift package directory containing Package.swift. Uses session default if not specified.",
            ),
        ])
    ]

    /// The `timeout` property for a tool whose default rises on a cold build cache.
    ///
    /// - Parameter work: What the timeout bounds, such as `the build` or `the test run`.
    /// - Returns: The property, ready to merge into a tool's schema.
    public static func timeout(for work: String) -> [String: Value] {
        [
            "timeout": .object([
                "type": .string("integer"),
                "description": .string(
                    "Maximum time in seconds for \(work). Defaults to 300 (5 minutes), or 900 (15 minutes) on a cold build cache.",
                ),
            ])
        ]
    }
}

/// The compiler-probe parameters `swift_package_build` and `swift_package_test` share.
///
/// A diagnostic probe used to mean editing `Package.swift` to add `unsafeFlags`, building, and
/// restoring the manifest. A probe that crashed or was cancelled left the manifest dirty, and
/// `unsafeFlags` can never be committed because SwiftPM refuses a package that declares it when
/// consumed by version. These parameters carry the same flags per invocation, so no probe touches a
/// tracked file.
public struct SwiftDiagnosticOptions: Sendable {
    /// Flags to forward to the compiler, each spelled as `swiftc` spells it.
    public let swiftcFlags: [String]
    /// A file to receive the streamed build output instead of the MCP response.
    public let stderrPath: String?
    /// A regular expression a line must match to reach ``stderrPath``.
    public let stderrFilter: String?

    /// Reads the parameters out of a tool's arguments, defaulting each to absent.
    public init(from arguments: [String: Value]) {
        swiftcFlags = arguments.getStringArray("swiftc_flags")
        stderrPath = arguments.getString("stderr_path")
        stderrFilter = arguments.getString("stderr_filter")
    }

    /// Opens the output sink when the caller asked for one.
    ///
    /// - Returns: The sink, or `nil` when no `stderr_path` was given.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the file or the filter is unusable.
    public func makeSink() throws(MCPError) -> StreamedOutputSink? {
        guard let stderrPath else {
            guard stderrFilter == nil else {
                throw MCPError.invalidParams(
                    "`stderr_filter` needs `stderr_path`: the filter selects which lines reach the "
                        + "file, and there is no file to write without it.",
                )
            }
            return nil
        }
        // The catch takes no pattern on purpose. The initializer throws SinkError alone, so error
        // binds to that type, and a pattern here would leave an unreachable implicit rethrow that
        // crashes SILGen in Swift 6.4.
        do {
            return try StreamedOutputSink(path: stderrPath, filter: stderrFilter)
        } catch {
            throw MCPError.invalidParams(error.description)
        }
    }

    /// Fans one chunk of subprocess output out to the progress reporter and the file sink.
    ///
    /// - Parameters:
    ///   - onProgress: The MCP progress callback, absent when the client sent no progress token.
    ///   - sink: The file sink, absent when the caller passed no `stderr_path`.
    /// - Returns: One callback, or `nil` when neither destination exists.
    public static func combine(
        _ onProgress: (@Sendable (String) -> Void)?,
        _ sink: StreamedOutputSink?,
    ) -> (@Sendable (String) -> Void)? {
        switch (onProgress, sink) {
            case (nil, nil): nil
            case let (progress?, nil): progress
            case let (nil, sink?): { sink.receive($0) }
            case let (progress?, sink?):
                {
                    progress($0)
                    sink.receive($0)
                }
        }
    }

    /// The JSON-schema properties every tool that accepts these parameters declares.
    public static let schemaProperties: [String: Value] = [
        "swiftc_flags": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(
                "Flags forwarded to the compiler, one -Xswiftc per element. Write each flag the way swiftc spells it, e.g. [\"-Xllvm\", \"-inline-threshold=0\", \"-num-threads\", \"1\"]. Use this instead of editing Package.swift to add unsafeFlags.",
            ),
        ]),
        "stderr_path": .object([
            "type": .string("string"),
            "description": .string(
                "File to stream the build output to instead of returning it. Use this for a verbose compiler probe, whose output can reach gigabytes and never fits a response.",
            ),
        ]),
        "stderr_filter": .object([
            "type": .string("string"),
            "description": .string(
                "Regular expression a line must match to reach stderr_path. Applied while the output streams, so a filtered probe writes a small file. Requires stderr_path.",
            ),
        ]),
    ]
}
