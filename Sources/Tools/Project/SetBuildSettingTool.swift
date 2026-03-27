import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct SetBuildSettingTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "set_build_setting",
            description:
            "Modify build settings for a target or the project. Omit target_name to set project-level build settings.",
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
                            "Name of the target to modify. Omit to set project-level build settings.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration name (Debug, Release, or All)"),
                    ]),
                    "setting_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the build setting to modify"),
                    ]),
                    "setting_value": .object([
                        "type": .string("string"),
                        "description": .string("New value for the build setting"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("configuration"),
                    .string("setting_name"), .string("setting_value"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(configuration) = arguments["configuration"],
              case let .string(settingName) = arguments["setting_name"],
              case let .string(settingValue) = arguments["setting_value"]
        else {
            throw MCPError.invalidParams(
                "project_path, configuration, setting_name, and setting_value are required",
            )
        }

        let targetName: String?
        if case let .string(name) = arguments["target_name"] {
            targetName = name
        } else {
            targetName = nil
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let configList: XCConfigurationList
            let scopeLabel: String

            if let targetName {
                // Target-level build settings
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

                guard let list = target.buildConfigurationList else {
                    return CallTool.Result(
                        content: [
                            .text("Target '\(targetName)' has no build configuration list"),
                        ],
                    )
                }
                configList = list
                scopeLabel = "target '\(targetName)'"
            } else {
                // Project-level build settings
                guard let project = xcodeproj.pbxproj.rootObject,
                      let list = project.buildConfigurationList
                else {
                    return CallTool.Result(
                        content: [
                            .text("Project has no build configuration list"),
                        ],
                    )
                }
                configList = list
                scopeLabel = "project"
            }

            var modifiedConfigurations: [String] = []

            // Handle "All" configuration
            if configuration.lowercased() == "all" {
                for config in configList.buildConfigurations {
                    config.buildSettings[settingName] = .string(settingValue)
                    modifiedConfigurations.append(config.name)
                }
            } else {
                // Find specific configuration
                guard
                    let config = configList.buildConfigurations.first(where: {
                        $0.name == configuration
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Configuration '\(configuration)' not found for \(scopeLabel)",
                            ),
                        ],
                    )
                }

                config.buildSettings[settingName] = .string(settingValue)
                modifiedConfigurations.append(config.name)
            }

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let configurationsText = modifiedConfigurations.joined(separator: ", ")
            return CallTool.Result(
                content: [
                    .text(
                        "Successfully set '\(settingName)' to '\(settingValue)' for \(scopeLabel) in configuration(s): \(configurationsText)",
                    ),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to set build setting in Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
