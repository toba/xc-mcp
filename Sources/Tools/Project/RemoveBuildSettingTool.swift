import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveBuildSettingTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_build_setting",
            description:
            "Delete a build setting key from a target's (or the project's) buildSettings dict for the given configuration. No-op if the key isn't present. Use this when you want the setting to fall back to the xcconfig/project-level default rather than being explicitly set to an empty string.",
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
                        "description": .string(
                            "Name of the target to modify. Omit to remove from project-level build settings.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration name (e.g. Debug, Release) or 'All'"),
                    ]),
                    "setting_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the build setting key to remove"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("configuration"), .string("setting_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(configuration) = arguments["configuration"],
              case let .string(settingName) = arguments["setting_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, configuration, and setting_name are required",
            )
        }

        let targetName: String?
        if case let .string(name) = arguments["target_name"] {
            targetName = name
        } else {
            targetName = nil
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let configList: XCConfigurationList
            let scopeLabel: String

            if let targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                text: "Target '\(targetName)' not found in project",
                                annotations: nil,
                                _meta: nil,
                            ),
                        ],
                    )
                }

                guard let list = target.buildConfigurationList else {
                    return CallTool.Result(
                        content: [
                            .text(
                                text: "Target '\(targetName)' has no build configuration list",
                                annotations: nil,
                                _meta: nil,
                            ),
                        ],
                    )
                }
                configList = list
                scopeLabel = "target '\(targetName)'"
            } else {
                guard let project = xcodeproj.pbxproj.rootObject,
                      let list = project.buildConfigurationList
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                text: "Project has no build configuration list",
                                annotations: nil,
                                _meta: nil,
                            ),
                        ],
                    )
                }
                configList = list
                scopeLabel = "project"
            }

            var removedFrom: [String] = []
            var notPresentIn: [String] = []

            let targetConfigs: [XCBuildConfiguration]
            if configuration.lowercased() == "all" {
                targetConfigs = configList.buildConfigurations
            } else {
                guard
                    let config = configList.buildConfigurations.first(where: {
                        $0.name == configuration
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(text:
                                "Configuration '\(configuration)' not found for \(scopeLabel)",
                                annotations: nil, _meta: nil),
                        ],
                    )
                }
                targetConfigs = [config]
            }

            for config in targetConfigs {
                if config.buildSettings[settingName] != nil {
                    config.buildSettings.removeValue(forKey: settingName)
                    removedFrom.append(config.name)
                } else {
                    notPresentIn.append(config.name)
                }
            }

            // Only write if we actually changed something.
            if !removedFrom.isEmpty {
                try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))
            }

            var message = ""
            if removedFrom.isEmpty {
                message = "'\(settingName)' was not set for \(scopeLabel) in configuration(s): "
                    + notPresentIn.joined(separator: ", ")
                    + " — no changes made."
            } else {
                message = "Removed '\(settingName)' from \(scopeLabel) in configuration(s): "
                    + removedFrom.joined(separator: ", ")
                if !notPresentIn.isEmpty {
                    message += " (not present in: " + notPresentIn.joined(separator: ", ") + ")"
                }
            }

            return CallTool.Result(
                content: [
                    .text(text: message, annotations: nil, _meta: nil),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove build setting from Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
