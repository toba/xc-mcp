import XcodeProj
import Foundation

/// Identifies one entry inside a build phase
///
/// A caller names an entry by its file name, its path, or the product name of a Swift package
/// product. The remove, attribute, platform-filter and merge tools resolve the same argument
/// through here, so all four answer the same name with the same entry.
enum CopyFilesPhaseEntry {
    /// The outcome of naming one entry in a phase.
    enum Resolution {
        case found(PBXBuildFile)
        /// Text explaining why the name answers to no entry or to several.
        case explained(String)
    }

    /// Whether `buildFile` answers to `name`.
    ///
    /// A cross-project dependency enters a phase as a reference proxy. That is a file element like
    /// any other, so its name and path match through the same checks.
    static func matches(_ buildFile: PBXBuildFile, name: String) -> Bool {
        if let product = buildFile.product, product.productName == name { return true }
        guard let file = buildFile.file else { return false }
        if file.name == name { return true }
        guard let path = file.path else { return false }
        return path == name || (path as NSString).lastPathComponent == name
    }

    /// Names `buildFile` for result text.
    static func label(for buildFile: PBXBuildFile) -> String {
        if let product = buildFile.product { return product.productName }
        if let file = buildFile.file { return file.path ?? file.name ?? file.uuid }
        return "<dangling \(buildFile.uuid)>"
    }

    /// The one entry `name` answers to, or the text explaining why it answers to none or to several
    ///
    /// A caller returns the explanation to the client unchanged. Both set tools resolve through
    /// here, so one name draws one answer whichever tool the client called.
    ///
    /// - Parameters:
    ///   - name: The entry name the caller supplied.
    ///   - phase: The phase to search.
    ///   - targetName: The target holding the phase, named in the explanation.
    static func resolve(
        named name: String,
        in phase: PBXCopyFilesBuildPhase,
        targetName: String,
    ) -> Resolution {
        let phaseLabel = CopyFilesPhaseLocator.label(for: phase)
        let entries = phase.files ?? []
        let matching = entries.filter { matches($0, name: name) }

        if matching.isEmpty {
            let present = entries.map { "  - " + label(for: $0) }
            let listing = present.isEmpty
                ? "The phase is empty."
                : "Entries in the phase:\n\(present.joined(separator: "\n"))"
            return .explained(
                "'\(name)' is not in Copy Files phase '\(phaseLabel)' of target '\(targetName)'. \(listing)",
            )
        }

        return matching.count > 1
            ? .explained(
                "'\(name)' matches \(matching.count) entries in Copy Files phase '\(phaseLabel)' of target '\(targetName)'. Use a more specific name.",
            )
            : .found(matching[0])
    }
}
