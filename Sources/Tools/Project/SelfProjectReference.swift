import XcodeProj
import Foundation

/// Detects and removes self-referencing sub-project entries in an Xcode project.
///
/// Xcode operations can accidentally introduce a `projectReferences` entry whose `ProjectRef` is a
/// `PBXFileReference` (`lastKnownFileType = "wrapper.pb-project"`) pointing at the project that
/// contains it — i.e. the project nested inside itself. These bogus entries (plus their empty
/// `Products` groups) cause Periphery to abort with
/// `Cannot calculate full path for file element "<Project>.xcodeproj"`, blocking the entire scan
/// with no partial results.
public enum SelfProjectReference {
    /// Returns the display names of `projectReferences` entries that point at the project itself
    /// (matched by `.xcodeproj` basename).
    public static func detect(in xcodeproj: XcodeProj, projectPath: String) -> [String] {
        guard let rootObject = xcodeproj.pbxproj.rootObject else { return [] }
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        var found = [String]()

        for entry in rootObject.projects {
            guard let projectRef = entry["ProjectRef"],
                  let refPath = projectRef.path ?? projectRef.name
            else { continue }
            let base = (refPath as NSString).lastPathComponent
            if base == projectName { found.append(base) }
        }
        return found
    }

    /// Removes self-referencing sub-project entries: the `ProjectRef` file reference, the
    /// `projectReferences` entry, and the associated empty `Products` group. Mutates `xcodeproj` in
    /// place and returns the display names that were removed.
    @discardableResult
    public static func remove(from xcodeproj: XcodeProj, projectPath: String) -> [String] {
        let pbxproj = xcodeproj.pbxproj
        guard let rootObject = pbxproj.rootObject else { return [] }
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent

        var removedNames = [String]()
        var remainingProjects = [[String: PBXFileElement]]()

        for entry in rootObject.projects {
            guard let projectRef = entry["ProjectRef"],
                  let refPath = projectRef.path ?? projectRef.name,
                  (refPath as NSString).lastPathComponent == projectName
            else {
                remainingProjects.append(entry)
                continue
            }

            removedNames.append((refPath as NSString).lastPathComponent)

            // Detach and delete the self-referencing project file reference.
            detach(projectRef, from: rootObject.mainGroup)
            pbxproj.delete(object: projectRef)

            // Delete the associated Products group if it carries no children.
            if let productGroup = entry["ProductGroup"] as? PBXGroup,
               productGroup.children.isEmpty
            {
                detach(productGroup, from: rootObject.mainGroup)
                pbxproj.delete(object: productGroup)
            }
        }

        if !removedNames.isEmpty { rootObject.projects = remainingProjects }
        return removedNames
    }

    /// Recursively removes `element` from `group`'s children (and nested groups).
    private static func detach(_ element: PBXFileElement, from group: PBXGroup?) {
        guard let group else { return }
        group.children.removeAll { $0 === element }
        for child in group.children {
            if let subgroup = child as? PBXGroup { detach(element, from: subgroup) }
        }
    }
}
