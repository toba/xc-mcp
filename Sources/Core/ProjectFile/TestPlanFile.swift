import MCP
import Foundation

public enum TestPlanFile {
    /// Reads a `.xctestplan` JSON file and returns the top-level dictionary.
    ///
    /// Every value keeps the type the file gave it, so a key this server never names survives the
    /// write that follows.
    public static func read(from path: String) throws -> [String: AnyValue] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        do {
            return try JSONDecoder().decode([String: AnyValue].self, from: data)
        } catch {
            throw TestPlanFileError.invalidFormat(path)
        }
    }

    /// Writes a `.xctestplan` JSON dictionary to disk with pretty-printing and sorted keys.
    public static func write(_ json: [String: AnyValue], to path: String) throws {
        let encoder = JSONEncoder()
        // Xcode writes a container path with a bare slash, so escaping one would change the file
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(json).write(to: URL(fileURLWithPath: path))
    }

    /// Extracts test target names from a test plan JSON dictionary.
    public static func targetNames(from json: [String: AnyValue]) -> [String] {
        targetEntries(from: json).map(\.name)
    }

    /// Extracts test target entries with name and enabled status from a test plan JSON dictionary.
    ///
    /// Targets without an explicit `"enabled"` key are treated as enabled (Xcode's default).
    public static func targetEntries(
        from json: [String: AnyValue],
    ) -> [(name: String, enabled: Bool)] {
        testTargets(in: json).compactMap { entry in
            guard let name = entry["target"]?.dictionaryValue?["name"]?.stringValue else {
                return nil
            }
            return (name: name, enabled: entry["enabled"]?.boolValue ?? true)
        }
    }

    /// The `testTargets` array, or an empty one when the plan declares no test target.
    public static func testTargets(in json: [String: AnyValue]) -> [[String: AnyValue]] {
        json["testTargets"]?.dictionaryArrayValue ?? []
    }

    /// Whether a `testTargets` entry names the given target
    public static func entry(_ entry: [String: AnyValue], names targetName: String) -> Bool {
        entry["target"]?.dictionaryValue?["name"]?.stringValue == targetName
    }

    /// Edits the option dictionary of one scope of a test plan
    ///
    /// A plan carries the same option keys in two places. The plan-level `defaultOptions` holds
    /// them for every target, and each entry in `testTargets` holds an override for one target. A
    /// `nil` target name selects the first, a name selects the second.
    ///
    /// - Parameters:
    ///   - json: The plan JSON, edited in place.
    ///   - targetName: The test target to edit, or `nil` for the plan-level defaults.
    ///   - transform: Edits the scope dictionary and returns the caller's own result.
    /// - Returns: Whatever `transform` returns.
    /// - Throws: `TestPlanFileError.noTestTargets` when a name is given and the plan declares no
    ///   test targets, or `TestPlanFileError.targetNotFound` when no entry carries that name.
    @discardableResult
    public static func mutateScope<T>(
        _ json: inout [String: AnyValue],
        targetName: String?,
        _ transform: (inout [String: AnyValue]) -> T,
    ) throws(TestPlanFileError) -> T {
        guard let targetName else {
            var defaults = json["defaultOptions"]?.dictionaryValue ?? [:]
            let result = transform(&defaults)
            json["defaultOptions"] = .dictionary(defaults)
            return result
        }

        guard json["testTargets"] != nil else { throw TestPlanFileError.noTestTargets }
        var entries = testTargets(in: json)

        guard let index = entries.firstIndex(where: { entry($0, names: targetName) }) else {
            throw TestPlanFileError.targetNotFound(targetName)
        }

        var scope = entries[index]
        let result = transform(&scope)
        entries[index] = scope
        json["testTargets"] = .dictionaries(entries)
        return result
    }

    /// Edits the `options` dictionary of one named configuration, or the plan-level defaults
    ///
    /// - Parameters:
    ///   - json: The plan JSON, edited in place.
    ///   - configurationName: The configuration to edit, or `nil` for `defaultOptions`.
    ///   - transform: Edits the options dictionary.
    /// - Throws: `TestPlanFileError.noConfigurations` or `TestPlanFileError.configurationNotFound`
    ///   when a name is given and it does not resolve.
    public static func mutateOptions(
        _ json: inout [String: AnyValue],
        configurationName: String?,
        _ transform: (inout [String: AnyValue]) -> Void,
    ) throws(TestPlanFileError) {
        guard let configurationName else {
            var defaults = json["defaultOptions"]?.dictionaryValue ?? [:]
            transform(&defaults)
            json["defaultOptions"] = .dictionary(defaults)
            return
        }

        guard let rawConfigurations = json["configurations"]?.arrayValue else {
            throw TestPlanFileError.noConfigurations
        }
        var configurations = rawConfigurations.compactMap(\.dictionaryValue)

        guard let index = configurations.firstIndex(where: {
            $0["name"]?.stringValue == configurationName
        }) else {
            throw TestPlanFileError.configurationNotFound(
                configurationName,
                available: configurations.compactMap { $0["name"]?.stringValue },
            )
        }

        var entry = configurations[index]
        var options = entry["options"]?.dictionaryValue ?? [:]
        transform(&options)
        entry["options"] = .dictionary(options)
        configurations[index] = entry
        json["configurations"] = .dictionaries(configurations)
    }

    /// Builds a `container:` path for a project URL, used in test plan target entries.
    ///
    /// Returns `"container:<project-filename>"`, e.g. `"container:MyApp.xcodeproj"`.
    public static func containerPath(for projectURL: URL) -> String {
        "container:\(projectURL.lastPathComponent)"
    }

    /// Recursively finds `.xctestplan` files under the given root directory.
    ///
    /// Returns tuples of `(path, json)` for each valid test plan file found.
    public static func findFiles(
        under root: String,
        maxDepth: Int = 5,
    ) -> [(path: String, json: [String: AnyValue])] {
        findPaths(under: root, maxDepth: maxDepth).compactMap { path in
            guard let json = try? read(from: path) else { return nil }
            return (path: path, json: json)
        }
    }

    /// Recursively finds test plan file paths under the given root directory
    ///
    /// A caller that reads a plan more than once uses this and reads the JSON itself, which spares
    /// the directory walk on the second pass.
    public static func findPaths(under root: String, maxDepth: Int = 5) -> [String] {
        let fm = FileManager.default
        var results: [String] = []

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else { return results }

        let rootURL = URL(fileURLWithPath: root).standardized

        for case let fileURL as URL in enumerator {
            // Enforce max depth
            let relative = fileURL.standardized.path.dropFirst(rootURL.path.count)
            let depth = relative.components(separatedBy: "/").count - 1

            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if fileURL.pathExtension == "xctestplan" { results.append(fileURL.path) }
        }

        return results
    }

    public enum TestPlanFileError: Error, CustomStringConvertible, MCPErrorConvertible {
        case invalidFormat(String)
        case noTestTargets
        case targetNotFound(String)
        case noConfigurations
        case configurationNotFound(String, available: [String])

        public var description: String {
            switch self {
                case let .invalidFormat(path): "File at '\(path)' is not a valid test plan JSON"
                case .noTestTargets: "Test plan has no test targets"
                case let .targetNotFound(name): "Target '\(name)' not found in test plan"
                case .noConfigurations: "Test plan has no configurations"
                case let .configurationNotFound(name, available):
                    "Configuration '\(name)' not found in test plan."
                        + (available.isEmpty
                            ? ""
                            : " Available: \(available.joined(separator: ", "))")
            }
        }

        public func toMCPError() -> MCPError {
            switch self {
                case .invalidFormat: .internalError(description)
                default: .invalidParams(description)
            }
        }
    }
}
