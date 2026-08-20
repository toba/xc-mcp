import XcodeProj
import Foundation

/// The `sourceTree` and `path` a `PBXFileReference` needs to resolve to a file on disk.
struct FileReferenceLocation: Equatable {
    let sourceTree: PBXSourceTree
    let path: String
}

/// Computes where a `PBXFileReference` must point so Xcode resolves it to a real file.
///
/// A reference with `sourceTree` `.group` resolves its `path` against the directory of the group
/// that owns it. That directory chains up to the directory holding the `.xcodeproj`, and it is not
/// the directory the server was started in. A caller that stores a base-relative path on a `.group`
/// reference makes the group directory apply twice, and the reference stops resolving.
enum FileReferencePath {
    /// Returns the `sourceTree` and `path` for the file at `resolvedFilePath`.
    ///
    /// - Parameters:
    ///   - resolvedFilePath: Absolute path of the file.
    ///   - groupFullPath: Absolute path the owning group resolves to.
    ///   - projectRoot: Absolute path of the directory holding the `.xcodeproj`.
    ///   - basePath: Absolute path the server was started with.
    /// - Returns: The source tree and the path to store on the reference.
    static func location(
        forResolvedPath resolvedFilePath: String,
        groupFullPath: String,
        projectRoot: String,
        basePath: String,
    ) -> FileReferenceLocation {
        if resolvedFilePath.hasPrefix(groupFullPath + "/") {
            // The file sits inside the group directory, so the path stays group-relative.
            return FileReferenceLocation(
                sourceTree: .group,
                path: String(resolvedFilePath.dropFirst(groupFullPath.count + 1)),
            )
        }

        if resolvedFilePath.hasPrefix(projectRoot + "/") {
            // The file sits outside the group but inside the project directory.
            return FileReferenceLocation(
                sourceTree: .sourceRoot,
                path: String(resolvedFilePath.dropFirst(projectRoot.count + 1)),
            )
        }

        return resolvedFilePath.hasPrefix(basePath + "/")
            ? FileReferenceLocation(
                sourceTree: .sourceRoot,
                path: relativePath(from: projectRoot, to: resolvedFilePath),
            )
            : FileReferenceLocation(sourceTree: .absolute, path: resolvedFilePath)
    }

    /// Computes a relative path from `base` to `target` using `../` components.
    static func relativePath(from base: String, to target: String) -> String {
        let baseComponents = base.split(separator: "/", omittingEmptySubsequences: true)
        let targetComponents = target.split(separator: "/", omittingEmptySubsequences: true)

        // Find common prefix length
        var common = 0
        while common < baseComponents.count,
              common < targetComponents.count,
              baseComponents[common] == targetComponents[common]
        { common += 1 }

        // Go up from base to common ancestor, then down to target
        let ups = Array(repeating: "..", count: baseComponents.count - common)
        let downs = targetComponents[common...]
        return (ups + downs.map(String.init)).joined(separator: "/")
    }
}

extension PBXFileElement {
    /// Returns the absolute path the group owning this element resolves to.
    ///
    /// Falls back to `projectRoot` when the element has no parent group, or when the parent carries
    /// no resolvable path.
    func owningGroupFullPath(projectRoot: String) -> String {
        guard let parentGroup = parent as? PBXGroup else { return projectRoot }
        return ((try? parentGroup.fullPath(sourceRoot: projectRoot)) ?? nil) ?? projectRoot
    }
}
