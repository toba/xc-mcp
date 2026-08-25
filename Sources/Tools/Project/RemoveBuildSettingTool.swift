import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveBuildSettingTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
                        "description": .string(
                            "Build configuration name (e.g. Debug, Release) or 'All'"),
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
        guard let projectPath = arguments.getString("project_path"),
              let configuration = arguments.getString("configuration"),
              let settingName = arguments.getString("setting_name")
        else {
            throw MCPError.invalidParams(
                "project_path, configuration, and setting_name are required",
            )
        }

        let targetName = arguments.getString("target_name")

        do {
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

            var removedFrom: [String] = []
            var notPresentIn: [String] = []

            for config in scope.configurations {
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
                message = "'\(settingName)' was not set for \(scope.label) in configuration(s): "
                    + notPresentIn.joined(separator: ", ")
                    + " — no changes made."
            } else {
                message = "Removed '\(settingName)' from \(scope.label) in configuration(s): "
                    + removedFrom.joined(separator: ", ")
                if !notPresentIn.isEmpty {
                    message += " (not present in: " + notPresentIn.joined(separator: ", ") + ")"
                }
            }

            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }
}
