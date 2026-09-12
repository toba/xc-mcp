import XcodeProj

/// Identifies one dependency edge on a target
///
/// A caller names a dependency by the edge's own name, by the linked target's name, or by the
/// `remoteInfo` of its container proxy. The add tool wires all three, so a caller that remembers
/// any one of them reaches the edge.
enum TargetDependencyEntry {
    /// The outcome of naming one dependency on a target.
    enum Resolution {
        case found(PBXTargetDependency)
        /// Text explaining why the name answers to no dependency or to several.
        case explained(String)
    }

    /// Whether `dependency` answers to `name`.
    static func matches(_ dependency: PBXTargetDependency, name: String) -> Bool {
        if dependency.name == name { return true }
        if dependency.target?.name == name { return true }
        return dependency.targetProxy?.remoteInfo == name
    }

    /// Names `dependency` for result text.
    static func label(for dependency: PBXTargetDependency) -> String {
        dependency.name ?? dependency.target?.name ?? dependency.targetProxy?.remoteInfo
            ?? dependency.uuid
    }

    /// The one dependency `name` answers to, or the text explaining why it answers to none or to
    /// several
    ///
    /// A caller returns the explanation to the client unchanged.
    ///
    /// - Parameters:
    ///   - name: The dependency name the caller supplied.
    ///   - target: The target to search.
    static func resolve(named name: String, in target: PBXNativeTarget) -> Resolution {
        let matching = target.dependencies.filter { matches($0, name: name) }

        if matching.isEmpty {
            let present = target.dependencies.map { "  - " + label(for: $0) }
            let listing = present.isEmpty
                ? "The target has no dependencies."
                : "Dependencies of the target:\n\(present.joined(separator: "\n"))"
            return .explained(
                "Target '\(target.name)' has no dependency named '\(name)'. \(listing)",
            )
        }

        return matching.count > 1
            ? .explained(
                "Target '\(target.name)' has \(matching.count) dependencies named '\(name)'. Remove the duplicate first.",
            )
            : .found(matching[0])
    }
}
