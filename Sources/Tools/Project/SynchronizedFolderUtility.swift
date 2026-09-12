import MCP
import XcodeProj

enum SynchronizedFolderUtility {
    /// A synchronized root group paired with its full path within the project hierarchy.
    struct Match {
        let group: PBXFileSystemSynchronizedRootGroup
        /// Slash-joined path from the main group down to (and including) this sync group, e.g.
        /// `Core/Sources`.
        let fullPath: String
    }

    /// Recursively collects every `PBXFileSystemSynchronizedRootGroup` reachable from `group`,
    /// tracking the accumulated parent path so callers can disambiguate by full path.
    static func collectSyncGroups(
        in group: PBXGroup,
        parentPath: String = "",
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
                        ? component
                        : "\(parentPath)/\(component)"
                } else {
                    nextParent = parentPath
                }
                results.append(contentsOf: collectSyncGroups(in: childGroup, parentPath: nextParent)
                )
            }
        }
        return results
    }

    /// Returns true when `folderPath` identifies `match`, either as the leaf `path`, the exact full
    /// path, or a trailing path-component suffix of the full path (e.g. `Core/Sources` matches a
    /// full path of `Modules/Core/Sources`).
    private static func matches(_ match: Match, folderPath: String) -> Bool {
        let leaf = match.group.path ?? match.group.name ?? ""
        return leaf == folderPath
            || match.fullPath == folderPath
            || match.fullPath.hasSuffix("/\(folderPath)")
    }

    /// The outcome of a folder-path lookup
    enum Lookup {
        case none
        case one(Match)
        /// The full paths the argument matched, sorted
        case ambiguous([String])
    }

    /// Resolves a folder path to at most one synchronized root group, using the target (when
    /// provided) to disambiguate folders that share a leaf name
    ///
    /// A caller that treats "no match" as an ordinary reply calls this. A caller that treats it as
    /// an error calls `resolveSyncGroup` instead.
    ///
    /// - Parameters:
    ///   - folderPath: The leaf path, the full path, or a trailing suffix of the full path.
    ///   - target: Restricts the matches to this target's `fileSystemSynchronizedGroups`.
    static func lookUpSyncGroup(
        folderPath: String,
        target: PBXNativeTarget?,
        in mainGroup: PBXGroup,
    ) -> Lookup {
        var candidates = collectSyncGroups(in: mainGroup)
            .filter { matches($0, folderPath: folderPath) }
        if candidates.isEmpty { return .none }

        // Narrow by target membership when a target is provided. The target's
        // fileSystemSynchronizedGroups is the source of truth for which group a build exception
        // must attach to.
        if let target {
            let targetGroupUUIDs = Set((target.fileSystemSynchronizedGroups ?? []).map(\.uuid))

            if !targetGroupUUIDs.isEmpty {
                let narrowed = candidates.filter { targetGroupUUIDs.contains($0.group.uuid) }
                if !narrowed.isEmpty { candidates = narrowed }
            }
        }

        return candidates.count == 1
            ? .one(candidates[0])
            : .ambiguous(candidates.map(\.fullPath).sorted())
    }

    /// The reply for a folder path that matches more than one folder
    static func ambiguityMessage(folderPath: String, paths: [String]) -> String {
        "Synchronized folder '\(folderPath)' is ambiguous — it matches "
            + "\(paths.count) folders: \(paths.joined(separator: ", ")). "
            + "Disambiguate by passing one of these as folder_path."
    }

    /// Resolves a single synchronized root group for the given folder path, using the target (when
    /// provided) to disambiguate folders that share a leaf name.
    ///
    /// - When a target is supplied, matches are restricted to the target's
    ///   `fileSystemSynchronizedGroups`.
    /// - Throws `invalidParams` when nothing matches, or when the match is ambiguous and cannot be
    ///   narrowed by target or by a fuller `folderPath`.
    static func resolveSyncGroup(
        folderPath: String,
        target: PBXNativeTarget?,
        in mainGroup: PBXGroup,
    ) throws(MCPError) -> PBXFileSystemSynchronizedRootGroup {
        switch lookUpSyncGroup(folderPath: folderPath, target: target, in: mainGroup) {
            case .none:
                throw MCPError.invalidParams(
                    "Synchronized folder '\(folderPath)' not found in project")
            case let .one(match): return match.group
            case let .ambiguous(paths):
                throw MCPError.invalidParams(ambiguityMessage(folderPath: folderPath, paths: paths))
        }
    }

    /// Legacy leaf-only lookup retained for callers that don't disambiguate.
    static func findSyncGroup(
        _ path: String,
        in group: PBXGroup
    ) -> PBXFileSystemSynchronizedRootGroup? {
        collectSyncGroups(in: group)
            .first { $0.group.path == path || $0.fullPath == path }?.group
    }
}
