import XcodeProj

/// Helpers for reasoning about the on-disk paths that navigator groups and synchronized folders
/// resolve to.
///
/// A `PBXFileSystemSynchronizedRootGroup` stores its `path` relative to its parent group's
/// accumulated on-disk path (because `sourceTree == .group`). When a parent group is re-pathed or
/// moved, the accumulated path of everything beneath it changes — which silently breaks child
/// synchronized folders unless their `path` attributes are recomputed. These utilities make that
/// arithmetic reusable across `move_group`, `create_group`, and the folder tools.
enum OnDiskPath {
    /// A synchronized root group paired with the on-disk path it currently resolves to.
    struct SyncResolution {
        let group: PBXFileSystemSynchronizedRootGroup
        /// Project-root-relative on-disk path accumulated down to the sync group's parent.
        let parentAccumulated: String
        /// Project-root-relative on-disk path the sync group itself resolves to.
        let resolved: String
    }

    /// Collapses `.` and `..` components in a slash-separated relative path.
    static func normalize(_ path: String) -> String {
        var stack: [String] = []

        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            let c = String(component)

            switch c {
                case ".": continue
                case "..":
                    if let last = stack.last, last != ".." {
                        stack.removeLast()
                    } else {
                        stack.append("..")
                    }
                default: stack.append(c)
            }
        }
        return stack.joined(separator: "/")
    }

    /// Joins two relative path fragments and normalizes the result.
    static func join(_ base: String, _ leaf: String) -> String {
        if base.isEmpty { return normalize(leaf) }
        return leaf.isEmpty
            ? normalize(base)
            : normalize(base + "/" + leaf)
    }

    /// Expresses `target` relative to `base` (both project-root-relative), using `..` segments when
    /// `target` is not nested under `base`. Returns an empty string when the two are equal.
    static func relativize(_ target: String, from base: String) -> String {
        let t = normalize(target).split(separator: "/").map(String.init)
        let b = normalize(base).split(separator: "/").map(String.init)
        var i = 0
        while i < t.count, i < b.count, t[i] == b[i] { i += 1 }
        var components = Array(repeating: "..", count: b.count - i)
        components.append(contentsOf: t[i...])
        return components.joined(separator: "/")
    }

    /// The project-root-relative on-disk path `target` resolves to, walking the group tree from
    /// `mainGroup` and accumulating `.group`-sourceTree `path` attributes. Returns nil when
    /// `target` is not reachable from `mainGroup`.
    static func accumulated(of target: PBXGroup, in mainGroup: PBXGroup) -> String? {
        let rootAccumulated = component(of: mainGroup) ?? ""
        return target === mainGroup
            ? rootAccumulated
            : walk(mainGroup, accumulated: rootAccumulated, target: target)
    }

    /// Maps every synchronized folder reachable from `mainGroup` to the on-disk path it currently
    /// resolves to, keyed by object identity.
    static func syncResolutions(
        in mainGroup: PBXGroup,
    ) -> [ObjectIdentifier: SyncResolution] {
        var out: [ObjectIdentifier: SyncResolution] = [:]
        collectSync(in: mainGroup, accumulated: component(of: mainGroup) ?? "", into: &out)
        return out
    }

    // MARK: - Private

    /// The on-disk path component a group contributes (its `path` when it has a `.group`
    /// sourceTree), or nil when it is purely virtual.
    private static func component(of group: PBXGroup) -> String? {
        guard group.sourceTree == .group || group.sourceTree == nil,
              let path = group.path,
              !path.isEmpty else { return nil }
        return normalize(path)
    }

    private static func walk(
        _ group: PBXGroup,
        accumulated: String,
        target: PBXGroup,
    ) -> String? {
        for child in group.children {
            guard let g = child as? PBXGroup else { continue }
            let next = component(of: g).map { join(accumulated, $0) } ?? accumulated
            if g === target { return next }
            if let found = walk(g, accumulated: next, target: target) { return found }
        }
        return nil
    }

    private static func collectSync(
        in group: PBXGroup,
        accumulated: String,
        into out: inout [ObjectIdentifier: SyncResolution],
    ) {
        for child in group.children {
            if let sync = child as? PBXFileSystemSynchronizedRootGroup {
                out[ObjectIdentifier(sync)] = SyncResolution(
                    group: sync,
                    parentAccumulated: accumulated,
                    resolved: join(accumulated, sync.path ?? ""),
                )
            } else if let g = child as? PBXGroup {
                let next = component(of: g).map { join(accumulated, $0) } ?? accumulated
                collectSync(in: g, accumulated: next, into: &out)
            }
        }
    }
}
