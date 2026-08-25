import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct SetBuildSettingTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
        guard let projectPath = arguments.getString("project_path"),
              let configuration = arguments.getString("configuration"),
              let settingName = arguments.getString("setting_name"),
              let settingValue = arguments.getString("setting_value")
        else {
            throw MCPError.invalidParams(
                "project_path, configuration, setting_name, and setting_value are required",
            )
        }

        let targetName = arguments.getString("target_name")

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let scope: BuildSettingScope

            switch BuildSettingScope.resolve(
                in: xcodeproj, targetName: targetName, configuration: configuration,
            ) {
                case let .message(text): return CallTool.Result.text(text)
                case let .resolved(resolved): scope = resolved
            }

            for config in scope.configurations {
                config.buildSettings[settingName] = .string(settingValue)
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let configurationsText = scope.configurations.map(\.name).joined(separator: ", ")
            return CallTool.Result.text(
                "Successfully set '\(settingName)' to '\(settingValue)' for \(scope.label) in configuration(s): \(configurationsText)"
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
