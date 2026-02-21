import XcodeProj

enum SynchronizedFolderUtility {
    /// Recursively searches for a `PBXFileSystemSynchronizedRootGroup` matching the given path.
    static func findSyncGroup(_ path: String, in group: PBXGroup)
        -> PBXFileSystemSynchronizedRootGroup?
    {
        for child in group.children {
            if let syncGroup = child as? PBXFileSystemSynchronizedRootGroup,
                syncGroup.path == path
            {
                return syncGroup
            }
            if let childGroup = child as? PBXGroup {
                if let found = findSyncGroup(path, in: childGroup) {
                    return found
                }
            }
        }
        return nil
    }
}
