import MCP
import XCMCPCore
import XcodeProj

/// An object that carries Xcode's per-platform filter keys
///
/// Xcode writes `platformFilters` on a `PBXBuildFile` and on a `PBXTargetDependency`. It is the
/// Platforms column of a build phase's file list. The older singular `platformFilter` holds one
/// name, and the two keys never appear together.
protocol PlatformFilterable: AnyObject {
    var platformFilter: String? { get set }
    var platformFilters: [String]? { get set }
}

extension PBXBuildFile: PlatformFilterable {}

extension PBXTargetDependency: PlatformFilterable {}

/// Reads and writes the platform filters on a build file or a target dependency.
enum PlatformFilters {
    /// The platform names Xcode accepts in a filter list.
    static let known: Set<String> = [
        "macos", "ios", "maccatalyst", "tvos", "watchos", "xros", "visionos", "driverkit",
    ]

    /// The known names, sorted, for an error message.
    static var knownList: String { known.sorted().joined(separator: ", ") }

    /// Lowercases each name, because Xcode writes a filter in lower case.
    ///
    /// - Parameter filters: The names the caller supplied.
    /// - Returns: The normalized names, in the order the caller gave them, without a duplicate.
    /// - Throws: ``MCPError/invalidParams(_:)`` naming the first unknown platform.
    static func normalize(_ filters: [String]) throws(MCPError) -> [String] {
        var normalized: [String] = []
        normalized.reserveCapacity(filters.count)

        for filter in filters {
            let name = filter.lowercased()
            guard known.contains(name) else {
                throw .invalidParams(
                    "Unknown platform filter '\(filter)'. Use one of: \(knownList)")
            }
            if !normalized.contains(name) { normalized.append(name) }
        }
        return normalized
    }

    /// The platform filters a tool's arguments name, empty when the caller passed no such key.
    ///
    /// - Throws: ``MCPError/invalidParams(_:)`` naming the first unknown platform.
    static func requested(in arguments: [String: Value]) throws(MCPError) -> [String] {
        guard let requested = arguments.getOptionalStringArray("platform_filters") else {
            return []
        }
        return try normalize(requested)
    }

    /// The filters on an object, reading the singular key when the plural one is absent.
    static func read(_ object: some PlatformFilterable) -> [String] {
        if let filters = object.platformFilters { return filters }
        if let filter = object.platformFilter { return [filter] }
        return []
    }

    /// Names the filters for result text.
    static func describe(_ filters: [String]) -> String {
        filters.isEmpty ? "(none)" : "[\(filters.joined(separator: ", "))]"
    }

    /// Writes the filters, clearing both keys when the list is empty.
    ///
    /// The singular key always goes, because Xcode reads one key or the other and two of them
    /// disagree the moment either one changes.
    ///
    /// - Returns: `true` when the object changed.
    static func write(_ filters: [String], to object: some PlatformFilterable) -> Bool {
        let before = read(object)
        let hadSingular = object.platformFilter != nil

        object.platformFilter = nil
        object.platformFilters = filters.isEmpty ? nil : filters

        return before != filters || hadSingular
    }
}
