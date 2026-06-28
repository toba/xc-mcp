import XcodeProj

/// Removes every cross-cutting object that references a target and would be left dangling once the
/// target itself is deleted.
///
/// Both `remove_target` and `remove_app_extension` funnel target removal through here so a deleted
/// target can never leave behind a `PBXTargetDependency`, a container item proxy, a
/// `TargetAttributes` entry, or a synchronized-folder build-file exception set still pointing at it.
/// Those are precisely the dangling references that make Xcode fail to load a project — and that the
/// ``SafeProjectWrite`` referential-integrity audit now refuses to write.
enum TargetGraphCleanup {
    /// Detach and delete every object referencing `target` from `pbxproj`. The target's own build
    /// phases, configuration list, product reference, and group membership are the caller's
    /// responsibility; this handles only the references that live *outside* the target.
    static func removeReferences(to target: PBXTarget, in pbxproj: PBXProj) {
        let project = try? pbxproj.rootProject()

        // Other targets' dependencies on this target, plus their proxy objects.
        for other in (project?.targets ?? []) where other !== target {
            let stale = other.dependencies.filter { $0.target === target }
            for dependency in stale {
                if let proxy = dependency.targetProxy { pbxproj.delete(object: proxy) }
                pbxproj.delete(object: dependency)
            }
            other.dependencies.removeAll { $0.target === target }
        }

        // Any remaining container item proxies pointing at the target.
        let remoteGlobalID = PBXContainerItemProxy.RemoteGlobalID.object(target)
        for proxy in pbxproj.containerItemProxies where proxy.remoteGlobalID == remoteGlobalID {
            pbxproj.delete(object: proxy)
        }

        // The project's per-target attributes entry (keyed by the target's UUID).
        project?.removeTargetAttributes(target: target)

        // Synchronized-folder build-file exception sets owned by the target, detached from every
        // root group first so nothing references the now-deleted set.
        let orphanSets = pbxproj.fileSystemSynchronizedBuildFileExceptionSets
            .filter { $0.target === target }
        guard !orphanSets.isEmpty else { return }
        let ids = Set(orphanSets.map(ObjectIdentifier.init))
        for rootGroup in pbxproj.fileSystemSynchronizedRootGroups {
            rootGroup.exceptions?.removeAll { ids.contains(ObjectIdentifier($0 as AnyObject)) }
        }
        for set in orphanSets { pbxproj.delete(object: set) }
    }
}
