import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveTargetTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_target",
            description: "Remove an existing target",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to remove"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target to remove (check all target types, not just native)
            guard let project = xcodeproj.pbxproj.rootObject,
                  let target = project.targets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(
                    content: [
                        .text("Target '\(targetName)' not found in project"),
                    ],
                )
            }

            // Remove target dependencies from other targets, plus their proxy objects
            let remoteGlobalID = PBXContainerItemProxy.RemoteGlobalID.object(target)
            for otherTarget in project.targets where otherTarget != target {
                let orphaned = otherTarget.dependencies.filter { $0.target == target }
                for dependency in orphaned {
                    if let proxy = dependency.targetProxy {
                        xcodeproj.pbxproj.delete(object: proxy)
                    }
                    xcodeproj.pbxproj.delete(object: dependency)
                }
                otherTarget.dependencies.removeAll { $0.target == target }
            }

            // Remove any remaining PBXContainerItemProxy entries referencing the target
            for proxy in xcodeproj.pbxproj.containerItemProxies
                where proxy.remoteGlobalID == remoteGlobalID
            {
                xcodeproj.pbxproj.delete(object: proxy)
            }

            // Remove build phases
            for buildPhase in target.buildPhases {
                xcodeproj.pbxproj.delete(object: buildPhase)
            }

            // Remove build configuration list
            if let configList = target.buildConfigurationList {
                for config in configList.buildConfigurations {
                    xcodeproj.pbxproj.delete(object: config)
                }
                xcodeproj.pbxproj.delete(object: configList)
            }

            // Remove product reference if exists
            if let productRef = target.product {
                project.productsGroup?.children.removeAll { $0 == productRef }
                xcodeproj.pbxproj.delete(object: productRef)
            }

            // Remove target from project
            project.targets.removeAll { $0 == target }

            // Remove target group if exists
            if let project = try xcodeproj.pbxproj.rootProject(),
               let mainGroup = project.mainGroup
            {
                /// Find and remove target folder
                func removeTargetGroup(from group: PBXGroup) {
                    group.children.removeAll { element in
                        if let groupElement = element as? PBXGroup,
                           groupElement.name == targetName
                        {
                            xcodeproj.pbxproj.delete(object: groupElement)
                            return true
                        }
                        return false
                    }

                    // Recursively check child groups
                    for child in group.children {
                        if let childGroup = child as? PBXGroup {
                            removeTargetGroup(from: childGroup)
                        }
                    }
                }
                removeTargetGroup(from: mainGroup)
            }

            // Remove the target itself
            xcodeproj.pbxproj.delete(object: target)

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text("Successfully removed target '\(targetName)' from project"),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove target from Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
