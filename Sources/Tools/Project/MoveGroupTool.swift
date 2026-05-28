import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Moves a navigator group (PBXGroup or PBXFileSystemSynchronizedRootGroup) from
/// one parent group to another, with the option to rewrite its `path` attribute.
///
/// Useful for fixing up navigator hierarchies — for example, nesting a sibling
/// `FooTests` group under its sibling `Foo` so the layout matches Apple's
/// recommended `Foo/{Sources,Tests}` convention.
public struct MoveGroupTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "move_group",
            description:
            "Move a navigator group (PBXGroup or synchronized folder) under a different parent group. Optionally rewrite the group's path attribute (e.g. when the new parent already contributes the prefix).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "group_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Slash-separated path identifying the group to move, matched by group name or path (e.g. 'ModelsTests' or 'Modules/ModelsTests'). Top-level groups match by their name or path at the project root.",
                        ),
                    ]),
                    "new_parent": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Slash-separated path of the destination parent group, or empty/omitted to move under the project's main group.",
                        ),
                    ]),
                    "new_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: rewrite the moved group's `path` attribute. Use empty string to clear the path (group becomes name-only).",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("group_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(groupPath) = arguments["group_path"]
        else {
            throw MCPError.invalidParams("project_path and group_path are required")
        }

        let newParentPath: String?
        if case let .string(np) = arguments["new_parent"], !np.isEmpty {
            newParentPath = np
        } else {
            newParentPath = nil
        }

        let newPathRewrite: String?
        if case let .string(p) = arguments["new_path"] {
            newPathRewrite = p
        } else {
            newPathRewrite = nil
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))
            guard let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup else {
                throw MCPError.internalError("Main group not found in project")
            }

            // Locate the group to move and its current parent.
            guard let (target, currentParent) = locate(
                groupPath: groupPath, under: mainGroup,
            ) else {
                throw MCPError.invalidParams("Group '\(groupPath)' not found in project")
            }

            // Resolve destination parent.
            let destination: PBXGroup
            if let newParentPath {
                destination = try mainGroup.resolveGroupPath(newParentPath)
            } else {
                destination = mainGroup
            }

            // Guard against moving a group under itself or a descendant.
            if let targetGroup = target as? PBXGroup,
               destination !== currentParent,
               isDescendant(destination, of: targetGroup)
            {
                throw MCPError.invalidParams(
                    "Cannot move group '\(groupPath)' under itself or one of its descendants",
                )
            }

            let parentChanged = destination !== currentParent
            if parentChanged {
                currentParent.children.removeAll { $0 === target }
                destination.children.append(target)
            }

            // Optionally rewrite the path attribute (works for both PBXGroup and sync roots).
            if let newPathRewrite {
                let normalized = newPathRewrite.isEmpty ? nil : newPathRewrite
                if let g = target as? PBXGroup {
                    g.path = normalized
                } else if let s = target as? PBXFileSystemSynchronizedRootGroup {
                    s.path = normalized
                }
            }

            if !parentChanged, newPathRewrite == nil {
                return CallTool.Result(
                    content: [.text(
                        text: "Group '\(groupPath)' is already under the requested parent",
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let dest = newParentPath ?? "<main group>"
            var msg: String
            if parentChanged {
                msg = "Moved '\(groupPath)' under '\(dest)'"
            } else {
                msg = "Updated path on '\(groupPath)'"
            }
            if let newPathRewrite {
                if newPathRewrite.isEmpty {
                    msg += " (cleared path)"
                } else {
                    msg += " (path = '\(newPathRewrite)')"
                }
            }
            return CallTool.Result(
                content: [.text(text: msg, annotations: nil, _meta: nil)],
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Walks the group tree to find the target group and its parent. Supports both
    /// PBXGroup and PBXFileSystemSynchronizedRootGroup as the final segment.
    private func locate(
        groupPath: String,
        under root: PBXGroup,
    ) -> (target: PBXFileElement, parent: PBXGroup)? {
        let components = groupPath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }

        var parent: PBXGroup = root
        for component in components.dropLast() {
            guard
                let next = parent.children
                .compactMap({ $0 as? PBXGroup })
                .first(where: { $0.name == component || $0.path == component })
            else { return nil }
            parent = next
        }
        let last = components.last!
        guard
            let match = parent.children.first(where: { child in
                if let g = child as? PBXGroup {
                    return g.name == last || g.path == last
                }
                if let s = child as? PBXFileSystemSynchronizedRootGroup {
                    return s.name == last || s.path == last
                }
                return false
            })
        else { return nil }
        return (match, parent)
    }

    /// Returns true if `candidate` is `ancestor` itself or any descendant of it.
    private func isDescendant(_ candidate: PBXGroup, of ancestor: PBXGroup) -> Bool {
        if candidate === ancestor { return true }
        for child in ancestor.children {
            if let g = child as? PBXGroup, isDescendant(candidate, of: g) {
                return true
            }
        }
        return false
    }
}
