import MCP
import Foundation

/// The severity floor a unified-log command reads
public enum UnifiedLogLevel: String, Sendable, CaseIterable {
    case `default`
    case info
    case debug

    /// The `log` flag that widens the output to this level, `nil` for the default level.
    public var flag: String? {
        switch self {
            case .default: nil
            case .info: "--info"
            case .debug: "--debug"
        }
    }

    /// Schema property for the level argument.
    public static var schemaProperty: [String: Value] {
        [
            "level": .object([
                "type": .string("string"),
                "enum": .array(allCases.map { .string($0.rawValue) }),
                "description": .string(
                    "Log level to include: 'default', 'info', or 'debug'. Default is 'default' "
                        + "which excludes info/debug messages. Use 'info' or 'debug' to include "
                        + "lower-severity messages.",
                ),
            ])
        ]
    }
}

/// A filter over the macOS unified log
///
/// `log stream` and `log show` take the same level flags and the same predicate, so
/// `start_mac_log_cap` and `show_mac_log` build both here. The two commands differ only in the
/// subcommand and in the time-range flags `log show` adds.
public struct UnifiedLogQuery: Sendable {
    public let bundleID: String?
    public let processName: String?
    public let subsystem: String?
    /// A predicate the caller wrote, which replaces the one the other three fields build.
    public let customPredicate: String?
    public let level: UnifiedLogLevel?

    /// Reads and validates the five filter arguments both log tools take.
    ///
    /// - Parameter arguments: The tool call arguments.
    /// - Throws: ``PredicateFilterError`` when a field holds a value that is unsafe to interpolate
    ///   into a predicate.
    public init(arguments: [String: Value]) throws(PredicateFilterError) {
        bundleID = arguments.getString("bundle_id")
        processName = arguments.getString("process_name")
        subsystem = arguments.getString("subsystem")
        customPredicate = arguments.getString("predicate")
        level = arguments.getString("level").flatMap(UnifiedLogLevel.init(rawValue:))

        if let bundleID { try PredicateFilterValidator.validate(bundleID, field: "bundle_id") }
        if let processName {
            try PredicateFilterValidator.validateStringLiteral(processName, field: "process_name")
        }
        if let subsystem { try PredicateFilterValidator.validate(subsystem, field: "subsystem") }
    }

    /// The predicate the `log` command filters on, or `nil` when the query filters nothing.
    ///
    /// Resolving a bundle identifier reads the app bundle on disk, so this is async. Call it once
    /// and pass the result to ``commandArguments(subcommand:predicate:extra:)``. The result also
    /// belongs in the tool's reply, because the caller needs to see what was filtered.
    public func resolvedPredicate() async -> String? {
        if let customPredicate { return customPredicate }

        var parts: [String] = []

        if let bundleID {
            // The last component of a bundle ID may not match the binary name, such as
            // "com.thesisapp.testapp" for an executable named "TestApp". Read the bundle when it is
            // there, and match case-insensitively when it is not.
            if let resolved = await Self.resolveExecutableName(bundleID: bundleID) {
                parts.append("process == \"\(resolved)\"")
            } else {
                let appName = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
                parts.append("process ==[cd] \"\(appName)\"")
            }
        }
        if let processName {
            let escaped = PredicateFilterValidator.escapeStringLiteral(processName)
            parts.append("process == \"\(escaped)\"")
        }
        if let subsystem { parts.append("subsystem == \"\(subsystem)\"") }

        return parts.isEmpty ? nil : parts.joined(separator: " AND ")
    }

    /// Builds the argument list for `/usr/bin/log`.
    ///
    /// - Parameters:
    ///   - subcommand: `stream` or `show`.
    ///   - predicate: The value ``resolvedPredicate()`` returned.
    ///   - extra: Flags the subcommand takes on its own, such as the `log show` time range. They
    ///     land after the level flags and before the predicate.
    public func commandArguments(
        subcommand: String,
        predicate: String?,
        extra: [String] = [],
    ) -> [String] {
        var args = [subcommand, "--style", "compact"]
        if let flag = level?.flag { args.append(flag) }
        args.append(contentsOf: extra)
        if let predicate { args.append(contentsOf: ["--predicate", predicate]) }
        return args
    }

    /// Schema properties for the filter arguments both log tools take.
    public static var schemaProperties: [String: Value] {
        [
            "bundle_id": .object([
                "type": .string("string"),
                "description": .string(
                    "Optional bundle identifier to filter logs to a specific app. Uses the last "
                        + "component as the executable name (e.g., 'com.example.MyApp' matches "
                        + "process 'MyApp').",
                ),
            ]),
            "process_name": .object([
                "type": .string("string"),
                "description": .string(
                    "Optional process name to filter logs to a specific process. May contain "
                        + "spaces and parentheses (e.g., 'ThesisApp (debug)' from a "
                        + "build_debug_macos launch).",
                ),
            ]),
            "subsystem": .object([
                "type": .string("string"),
                "description": .string(
                    "Optional OSLog subsystem to filter logs (e.g., 'com.apple.CloudKit').",
                ),
            ]),
            "predicate": .object([
                "type": .string("string"),
                "description": .string(
                    "Optional custom predicate to filter logs. Overrides bundle_id, process_name, "
                        + "and subsystem filters.",
                ),
            ]),
        ].merging(UnifiedLogLevel.schemaProperty) { _, new in new }
    }

    /// Resolves the executable name from an app bundle's `Info.plist`.
    ///
    /// Locates the app by bundle identifier with `mdfind`, then reads `CFBundleExecutable`.
    ///
    /// - Parameter bundleID: The bundle identifier to look up.
    /// - Returns: The executable name, or `nil` when no bundle matches.
    public static func resolveExecutableName(bundleID: String) async -> String? {
        guard let result = try? await ProcessResult.run(
            "/usr/bin/mdfind",
            arguments: ["kMDItemCFBundleIdentifier == '\(bundleID)'"],
            timeout: .seconds(5),
        ),
              result.succeeded else { return nil }

        guard let appPath = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first(where: { $0.hasSuffix(".app") }),
            !appPath.isEmpty else { return nil }

        let infoPlistURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                  as? [String: Any],
              let executable = plist["CFBundleExecutable"] as? String else { return nil }

        return executable
    }
}
