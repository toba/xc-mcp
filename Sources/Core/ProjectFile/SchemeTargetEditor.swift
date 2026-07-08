import Foundation

/// Detects and removes references to a target inside `.xcscheme` files.
///
/// Schemes are edited as raw XML (not through XcodeProj's `XCScheme` model) because a model
/// round-trip silently drops elements XcodeProj does not model — e.g. a `TestAction`
/// `StoreKitConfigurationFileReference`. Removing only the wrapper element that owns a matching
/// `BuildableReference` keeps every other part of the scheme intact.
public enum SchemeTargetEditor {
    /// All `.xcscheme` file paths under the project's shared and user scheme directories.
    public static func schemeFiles(in projectPath: String) -> [String] {
        let fm = FileManager.default
        var results: [String] = []

        for dir in SchemePathResolver.schemeDirs(for: projectPath) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".xcscheme") {
                results.append("\(dir)/\(entry)")
            }
        }
        return results
    }

    /// True if the scheme at `path` references `targetName` and the reference belongs to this
    /// project (matched by the scheme's `ReferencedContainer`, when present).
    public static func references(
        target targetName: String,
        projectFilename: String,
        schemeAt path: String,
    ) -> Bool {
        guard let doc = try? XMLDocument(contentsOf: URL(fileURLWithPath: path)) else {
            return false
        }
        let nodes =
            (try? matchingReferences(in: doc, target: targetName, projectFilename: projectFilename))
            ?? []
        return !nodes.isEmpty
    }

    /// Removes every wrapper element that owns a `BuildableReference` for `targetName` from the
    /// scheme at `path`. Returns `true` when the scheme was modified.
    @discardableResult
    public static func removeTarget(
        named targetName: String,
        projectFilename: String,
        fromSchemeAt path: String,
    ) throws -> Bool {
        let url = URL(fileURLWithPath: path)
        let doc = try XMLDocument(contentsOf: url)
        let refs = try matchingReferences(
            in: doc, target: targetName, projectFilename: projectFilename)
        guard !refs.isEmpty else { return false }

        for ref in refs {
            // `BuildableReference` is always nested inside a wrapper (`BuildActionEntry`,
            // `TestableReference`, `MacroExpansion`, `BuildableProductRunnable`). Detach the
            // wrapper so the whole entry — not just the inner reference — is removed.
            let wrapper = (ref.parent as? XMLElement) ?? ref
            wrapper.detach()
        }

        let data = doc.xmlData(options: [.nodePrettyPrint])
        try data.write(to: url, options: .atomic)
        return true
    }

    private static func matchingReferences(
        in doc: XMLDocument,
        target targetName: String,
        projectFilename: String,
    ) throws -> [XMLElement] {
        try doc.nodes(forXPath: "//BuildableReference").compactMap { node in
            guard let element = node as? XMLElement,
                  element.attribute(forName: "BlueprintName")?.stringValue == targetName
            else { return nil }

            // When the reference names a container, only match it if it is this project's.
            if let container = element.attribute(forName: "ReferencedContainer")?.stringValue,
               !container.hasSuffix(projectFilename) { return nil }
            return element
        }
    }
}
