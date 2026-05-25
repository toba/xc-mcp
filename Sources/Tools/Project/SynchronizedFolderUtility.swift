import MCP
import XcodeProj

enum SynchronizedFolderUtility {
    /// A synchronized root group paired with its full path within the project hierarchy.
    struct Match {
        let group: PBXFileSystemSynchronizedRootGroup
        /// Slash-joined path from the main group down to (and including) this sync group,
        /// e.g. `Core/Sources`.
        let fullPath: String
    }

    /// Recursively collects every `PBXFileSystemSynchronizedRootGroup` reachable from `group`,
    /// tracking the accumulated parent path so callers can disambiguate by full path.
    static func collectSyncGroups(
        in group: PBXGroup, parentPath: String = "",
    ) -> [Match] {
        var results: [Match] = []
        for child in group.children {
            if let syncGroup = child as? PBXFileSystemSynchronizedRootGroup {
                let leaf = syncGroup.path ?? syncGroup.name ?? ""
                let full = parentPath.isEmpty ? leaf : "\(parentPath)/\(leaf)"
                results.append(Match(group: syncGroup, fullPath: full))
            } else if let childGroup = child as? PBXGroup {
                let component = childGroup.path ?? childGroup.name
                let nextParent: String
                if let component, !component.isEmpty {
                    nextParent = parentPath.isEmpty
                        ? component : "\(parentPath)/\(component)"
                } else {
                    nextParent = parentPath
                }
                results.append(
                    contentsOf: collectSyncGroups(
                        in: childGroup, parentPath: nextParent,
                    ),
                )
            }
        }
        return results
    }

    /// Returns true when `folderPath` identifies `match`, either as the leaf `path`,
    /// the exact full path, or a trailing path-component suffix of the full path
    /// (e.g. `Core/Sources` matches a full path of `Modules/Core/Sources`).
    private static func matches(_ match: Match, folderPath: String) -> Bool {
        let leaf = match.group.path ?? match.group.name ?? ""
        if leaf == folderPath || match.fullPath == folderPath { return true }
        // Suffix match on whole components: "Core/Sources" vs "a/Core/Sources".
        return match.fullPath == folderPath
            || match.fullPath.hasSuffix("/\(folderPath)")
    }

    /// Resolves a single synchronized root group for the given folder path, using the
    /// target (when provided) to disambiguate folders that share a leaf name.
    ///
    /// - When a target is supplied, matches are restricted to the target's
    ///   `fileSystemSynchronizedGroups`.
    /// - Throws `invalidParams` when nothing matches, or when the match is ambiguous and
    ///   cannot be narrowed by target or by a fuller `folderPath`.
    static func resolveSyncGroup(
        folderPath: String,
        target: PBXNativeTarget?,
        in mainGroup: PBXGroup,
    ) throws -> PBXFileSystemSynchronizedRootGroup {
        let all = collectSyncGroups(in: mainGroup)
        var candidates = all.filter { matches($0, folderPath: folderPath) }

        if candidates.isEmpty {
            throw MCPError.invalidParams(
                "Synchronized folder '\(folderPath)' not found in project",
            )
        }

        // Narrow by target membership when a target is provided. The target's
        // fileSystemSynchronizedGroups is the source of truth for which group a build
        // exception must attach to.
        if let target {
            let targetGroupUUIDs = Set(
                (target.fileSystemSynchronizedGroups ?? []).map(\.uuid),
            )
            if !targetGroupUUIDs.isEmpty {
                let narrowed = candidates.filter {
                    targetGroupUUIDs.contains($0.group.uuid)
                }
                if !narrowed.isEmpty {
                    candidates = narrowed
                }
            }
        }

        if candidates.count == 1 {
            return candidates[0].group
        }

        let paths = candidates.map(\.fullPath).sorted()
        throw MCPError.invalidParams(
            "Synchronized folder '\(folderPath)' is ambiguous — it matches "
                + "\(candidates.count) folders: \(paths.joined(separator: ", ")). "
                + "Disambiguate by passing one of these as folder_path.",
        )
    }

    /// Legacy leaf-only lookup retained for callers that don't disambiguate.
    static func findSyncGroup(_ path: String, in group: PBXGroup)
        -> PBXFileSystemSynchronizedRootGroup?
    {
        collectSyncGroups(in: group)
            .first { $0.group.path == path || $0.fullPath == path }?.group
    }
}
