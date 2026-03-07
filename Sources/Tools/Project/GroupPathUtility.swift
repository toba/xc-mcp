import MCP
import XcodeProj

extension PBXGroup {
    /// Resolves a slash-separated group path (e.g. "Components/TableView") by walking
    /// child groups from this group. Each path component is matched against child group
    /// `name` or `path`.
    ///
    /// - Parameter groupPath: Slash-separated path of group names/paths.
    /// - Returns: The resolved group at the end of the path.
    /// - Throws: `MCPError.invalidParams` if any component is not found.
    func resolveGroupPath(_ groupPath: String) throws(MCPError) -> PBXGroup {
        let components = groupPath.split(separator: "/").map(String.init)
        var current: PBXGroup = self
        for component in components {
            guard
                let child = current.children
                .compactMap({ $0 as? PBXGroup })
                .first(where: { $0.name == component || $0.path == component })
            else {
                throw .invalidParams(
                    "Group '\(groupPath)' not found (failed at '\(component)')",
                )
            }
            current = child
        }
        return current
    }
}
