import MCP
import XcodeProj

/// Reads and writes the `ATTRIBUTES` list inside a build file's `settings`
///
/// Xcode shows the same list as the checkbox columns of a build phase's file list. A Copy Files
/// phase entry carries `CodeSignOnCopy` and `RemoveHeadersOnCopy`. A Frameworks phase entry carries
/// `Weak` and `Merge`. Xcode writes the key as a list, and an older project may hold one bare
/// string instead.
enum BuildFileAttributes {
    /// The flags a Copy Files phase entry accepts.
    static let copyFiles: Set<String> = ["CodeSignOnCopy", "RemoveHeadersOnCopy"]

    /// The Copy Files flags, sorted, for an error message.
    static var copyFilesList: String { copyFiles.sorted().joined(separator: ", ") }

    /// The attributes on a build file, reading a bare string as a one-element list.
    static func read(_ buildFile: PBXBuildFile) -> [String] { stored(in: buildFile).values }

    /// Names the attributes for result text.
    static func describe(_ attributes: [String]) -> String {
        attributes.isEmpty ? "(none)" : "[\(attributes.joined(separator: ", "))]"
    }

    /// Matches each name to the flag Xcode writes, ignoring the case the caller used.
    ///
    /// - Parameters:
    ///   - attributes: The names the caller supplied.
    ///   - allowed: The flags this phase type accepts.
    ///   - allowedList: The accepted flags, for the error message.
    /// - Returns: The canonical names, in the order the caller gave them, without a duplicate.
    /// - Throws: ``MCPError/invalidParams(_:)`` naming the first unrecognized flag.
    static func normalize(
        _ attributes: [String],
        allowed: Set<String>,
        allowedList: String,
    ) throws(MCPError) -> [String] {
        var normalized: [String] = []
        normalized.reserveCapacity(attributes.count)

        for attribute in attributes {
            guard let canonical = allowed.first(where: {
                $0.caseInsensitiveCompare(attribute) == .orderedSame
            }) else {
                throw .invalidParams("Unknown attribute '\(attribute)'. Use one of: \(allowedList)")
            }
            if !normalized.contains(canonical) { normalized.append(canonical) }
        }
        return normalized
    }

    /// Writes the attributes in place, removing the key when the list is empty.
    ///
    /// The build file keeps its position in the phase, because the entry itself is what changes.
    ///
    /// - Returns: `true` when the build file changed.
    static func write(_ attributes: [String], to buildFile: PBXBuildFile) -> Bool {
        let (before, wasBareString) = stored(in: buildFile)
        var settings = buildFile.settings ?? [:]

        if attributes.isEmpty {
            settings.removeValue(forKey: "ATTRIBUTES")
        } else {
            settings["ATTRIBUTES"] = .array(attributes)
        }
        buildFile.settings = settings.isEmpty ? nil : settings

        // rewriting a bare string as a list is a change even when the names match
        return before != attributes || wasBareString
    }

    private static func stored(in buildFile: PBXBuildFile) -> (values: [String], bare: Bool) {
        guard let setting = buildFile.settings?["ATTRIBUTES"] else { return ([], false) }

        switch setting {
            case let .array(values): return (values, false)
            case let .string(value): return ([value], true)
        }
    }
}
