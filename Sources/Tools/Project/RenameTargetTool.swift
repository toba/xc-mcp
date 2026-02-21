import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct RenameTargetTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "rename_target",
            description: "Rename an existing target in-place, updating all references",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Current name of the target to rename"),
                    ]),
                    "new_name": .object([
                        "type": .string("string"),
                        "description": .string("New name for the target"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("new_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(newName) = arguments["new_name"]
        else {
            throw MCPError.invalidParams("project_path, target_name, and new_name are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target to rename
            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                })
            else {
                return CallTool.Result(
                    content: [
                        .text("Target '\(targetName)' not found in project"),
                    ]
                )
            }

            // Check new name doesn't already exist
            if xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == newName }) {
                return CallTool.Result(
                    content: [
                        .text("Target '\(newName)' already exists in project"),
                    ]
                )
            }

            // 1. Update target name and product name
            target.name = newName
            target.productName = newName

            // 2. Update build settings in all configurations
            if let configList = target.buildConfigurationList {
                for config in configList.buildConfigurations {
                    // PRODUCT_NAME — replace if it matches old name
                    if config.buildSettings["PRODUCT_NAME"]?.stringValue == targetName {
                        config.buildSettings["PRODUCT_NAME"] = .string(newName)
                    }

                    // INFOPLIST_FILE — string-replace old name with new name
                    if let infoPlist = config.buildSettings["INFOPLIST_FILE"]?.stringValue,
                       infoPlist.contains(targetName)
                    {
                        let newInfoPlist = infoPlist.replacingOccurrences(
                            of: targetName, with: newName
                        )
                        config.buildSettings["INFOPLIST_FILE"] = .string(newInfoPlist)
                    }

                    // PRODUCT_MODULE_NAME — replace if it matches old name
                    if config.buildSettings["PRODUCT_MODULE_NAME"]?.stringValue == targetName {
                        config.buildSettings["PRODUCT_MODULE_NAME"] = .string(newName)
                    }
                }
            }

            // 3. Update dependencies in other targets
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                for dependency in otherTarget.dependencies where dependency.target == target {
                    dependency.name = newName
                    if let proxy = dependency.targetProxy {
                        proxy.remoteInfo = newName
                    }
                }
            }

            // 4. Update embed/copy-files phases referencing this target's product
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                for buildPhase in otherTarget.buildPhases {
                    guard let copyPhase = buildPhase as? PBXCopyFilesBuildPhase else { continue }
                    for buildFile in copyPhase.files ?? [] {
                        if let fileRef = buildFile.file,
                           let path = fileRef.path,
                           path.contains(targetName)
                        {
                            fileRef.path = path.replacingOccurrences(
                                of: targetName, with: newName
                            )
                        }
                    }
                }
            }

            // 5. Update product reference
            if let product = target.product {
                if let path = product.path, path.contains(targetName) {
                    product.path = path.replacingOccurrences(of: targetName, with: newName)
                }
                if let name = product.name, name.contains(targetName) {
                    product.name = name.replacingOccurrences(of: targetName, with: newName)
                }
            }

            // 6. Rename target group in main group hierarchy
            if let project = try xcodeproj.pbxproj.rootProject(),
               let mainGroup = project.mainGroup
            {
                func renameGroup(in group: PBXGroup) {
                    for child in group.children {
                        if let childGroup = child as? PBXGroup,
                           childGroup.name == targetName
                        {
                            childGroup.name = newName
                            if childGroup.path == targetName {
                                childGroup.path = newName
                            }
                        }
                        if let childGroup = child as? PBXGroup {
                            renameGroup(in: childGroup)
                        }
                    }
                }
                renameGroup(in: mainGroup)
            }

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully renamed target '\(targetName)' to '\(newName)'"
                    ),
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to rename target in Xcode project: \(error.localizedDescription)"
            )
        }
    }
}
