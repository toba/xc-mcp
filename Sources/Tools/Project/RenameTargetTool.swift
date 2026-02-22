import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

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
                            "Path to the .xcodeproj file (relative to current directory)",
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
                    "new_bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier for the renamed target (optional)",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("new_name"),
                ]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(newName) = arguments["new_name"]
        else {
            throw MCPError.invalidParams("project_path, target_name, and new_name are required")
        }

        let newBundleIdentifier: String?
        if case let .string(bundleId) = arguments["new_bundle_identifier"] {
            newBundleIdentifier = bundleId
        } else {
            newBundleIdentifier = nil
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
                    ],
                )
            }

            // Check new name doesn't already exist
            if xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == newName }) {
                return CallTool.Result(
                    content: [
                        .text("Target '\(newName)' already exists in project"),
                    ],
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
                            of: targetName, with: newName,
                        )
                        config.buildSettings["INFOPLIST_FILE"] = .string(newInfoPlist)
                    }

                    // PRODUCT_MODULE_NAME — replace if it matches old name
                    if config.buildSettings["PRODUCT_MODULE_NAME"]?.stringValue == targetName {
                        config.buildSettings["PRODUCT_MODULE_NAME"] = .string(newName)
                    }

                    // CODE_SIGN_ENTITLEMENTS — string-replace old name with new name in path
                    if let entitlements = config.buildSettings["CODE_SIGN_ENTITLEMENTS"]?
                        .stringValue,
                        entitlements.contains(targetName)
                    {
                        config.buildSettings["CODE_SIGN_ENTITLEMENTS"] = .string(
                            entitlements.replacingOccurrences(of: targetName, with: newName),
                        )
                    }

                    // Bundle identifier — update if new_bundle_identifier provided
                    if let newBundleIdentifier {
                        config.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] = .string(
                            newBundleIdentifier,
                        )
                        config.buildSettings["BUNDLE_IDENTIFIER"] = .string(newBundleIdentifier)
                    }
                }
            }

            // 3. Cross-target build settings scan
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                guard let configList = otherTarget.buildConfigurationList else { continue }
                for config in configList.buildConfigurations {
                    // TEST_TARGET_NAME — exact match replace
                    if config.buildSettings["TEST_TARGET_NAME"]?.stringValue == targetName {
                        config.buildSettings["TEST_TARGET_NAME"] = .string(newName)
                    }

                    // TEST_HOST — string-replace old name with new name
                    if let testHost = config.buildSettings["TEST_HOST"]?.stringValue,
                       testHost.contains(targetName)
                    {
                        config.buildSettings["TEST_HOST"] = .string(
                            testHost.replacingOccurrences(of: targetName, with: newName),
                        )
                    }

                    // LD_RUNPATH_SEARCH_PATHS — handle string or array
                    replaceBuildSettingValue(
                        in: &config.buildSettings,
                        key: "LD_RUNPATH_SEARCH_PATHS",
                        oldName: targetName,
                        newName: newName,
                    )

                    // FRAMEWORK_SEARCH_PATHS — handle string or array
                    replaceBuildSettingValue(
                        in: &config.buildSettings,
                        key: "FRAMEWORK_SEARCH_PATHS",
                        oldName: targetName,
                        newName: newName,
                    )
                }
            }

            // 4. Update dependencies in other targets
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                for dependency in otherTarget.dependencies where dependency.target == target {
                    dependency.name = newName
                    if let proxy = dependency.targetProxy {
                        proxy.remoteInfo = newName
                    }
                }
            }

            // 5. Update embed/copy-files phases referencing this target's product
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                for buildPhase in otherTarget.buildPhases {
                    guard let copyPhase = buildPhase as? PBXCopyFilesBuildPhase else { continue }
                    for buildFile in copyPhase.files ?? [] {
                        if let fileRef = buildFile.file,
                           let path = fileRef.path,
                           path.contains(targetName)
                        {
                            fileRef.path = path.replacingOccurrences(
                                of: targetName, with: newName,
                            )
                        }
                    }
                }
            }

            // 6. Update product reference
            if let product = target.product {
                if let path = product.path, path.contains(targetName) {
                    product.path = path.replacingOccurrences(of: targetName, with: newName)
                }
                if let name = product.name, name.contains(targetName) {
                    product.name = name.replacingOccurrences(of: targetName, with: newName)
                }
            }

            // 7. Rename target group in main group hierarchy
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

            // 8. Update scheme files
            let schemesUpdated = updateSchemeFiles(
                projectPath: projectURL.path,
                oldName: targetName,
                newName: newName,
            )

            var message = "Successfully renamed target '\(targetName)' to '\(newName)'"
            if schemesUpdated > 0 {
                message +=
                    " (updated \(schemesUpdated) scheme file\(schemesUpdated == 1 ? "" : "s"))"
            }

            return CallTool.Result(
                content: [.text(message)],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to rename target in Xcode project: \(error.localizedDescription)",
            )
        }
    }

    /// Replace old name with new name in a build setting that may be a string or array value.
    private func replaceBuildSettingValue(
        in buildSettings: inout BuildSettings,
        key: String,
        oldName: String,
        newName: String,
    ) {
        guard let value = buildSettings[key] else { return }
        switch value {
            case let .string(str):
                if str.contains(oldName) {
                    buildSettings[key] = .string(
                        str.replacingOccurrences(of: oldName, with: newName),
                    )
                }
            case let .array(arr):
                let updated = arr.map { $0.replacingOccurrences(of: oldName, with: newName) }
                if updated != arr {
                    buildSettings[key] = .array(updated)
                }
        }
    }

    /// Scan scheme files and replace BuildableName/BlueprintName references.
    /// Returns the number of scheme files updated.
    private func updateSchemeFiles(
        projectPath: String,
        oldName: String,
        newName: String,
    ) -> Int {
        let fm = FileManager.default
        var schemeDirs: [String] = []

        // Shared schemes
        let sharedDir = "\(projectPath)/xcshareddata/xcschemes"
        if fm.fileExists(atPath: sharedDir) {
            schemeDirs.append(sharedDir)
        }

        // User schemes
        let userdataDir = "\(projectPath)/xcuserdata"
        if let userDirs = try? fm.contentsOfDirectory(atPath: userdataDir) {
            for userDir in userDirs {
                let userSchemeDir = "\(userdataDir)/\(userDir)/xcschemes"
                if fm.fileExists(atPath: userSchemeDir) {
                    schemeDirs.append(userSchemeDir)
                }
            }
        }

        var updatedCount = 0

        for schemeDir in schemeDirs {
            guard let files = try? fm.contentsOfDirectory(atPath: schemeDir) else { continue }
            for file in files where file.hasSuffix(".xcscheme") {
                let schemePath = "\(schemeDir)/\(file)"
                guard var content = try? String(contentsOfFile: schemePath, encoding: .utf8)
                else { continue }

                let original = content

                // Replace BuildableName (preserves extension)
                content = content.replacingOccurrences(
                    of: "BuildableName = \"\(oldName).",
                    with: "BuildableName = \"\(newName).",
                )

                // Replace BlueprintName
                content = content.replacingOccurrences(
                    of: "BlueprintName = \"\(oldName)\"",
                    with: "BlueprintName = \"\(newName)\"",
                )

                if content != original {
                    try? content.write(toFile: schemePath, atomically: true, encoding: .utf8)
                    updatedCount += 1
                }
            }
        }

        return updatedCount
    }
}
