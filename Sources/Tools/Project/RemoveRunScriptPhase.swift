import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveRunScriptPhase: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_run_script_phase",
            description: "Remove a Run Script (PBXShellScriptBuildPhase) build phase from a target",
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
                        "description": .string("Name of the target containing the phase"),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the Run Script phase to remove. Matches PBXShellScriptBuildPhase.name; if unnamed, falls back to matching the default 'ShellScript'.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("phase_name"),
                ]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(phaseName) = arguments["phase_name"]
        else {
            throw MCPError.invalidParams("project_path, target_name, and phase_name are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(
                    content: [.text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            }

            // Find the run-script phase by name. Treat a nil name as the
            // implicit default "ShellScript" so callers can target unnamed phases.
            let matchingIndices = target.buildPhases.enumerated().compactMap {
                index, phase -> Int? in
                guard let shell = phase as? PBXShellScriptBuildPhase else { return nil }
                let resolvedName = shell.name ?? "ShellScript"
                return resolvedName == phaseName ? index : nil
            }

            guard let phaseIndex = matchingIndices.first else {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Run Script phase '\(phaseName)' not found in target '\(targetName)'",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            if matchingIndices.count > 1 {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Multiple Run Script phases named '\(phaseName)' found in target '\(targetName)'; rename them to disambiguate before removal",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            guard let shellPhase = target.buildPhases[phaseIndex] as? PBXShellScriptBuildPhase
            else {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Run Script phase '\(phaseName)' not found in target '\(targetName)'",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            // Remove any build files (rare for shell phases but possible).
            if let buildFiles = shellPhase.files {
                for buildFile in buildFiles {
                    xcodeproj.pbxproj.delete(object: buildFile)
                }
            }

            target.buildPhases.remove(at: phaseIndex)
            xcodeproj.pbxproj.delete(object: shellPhase)

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(text:
                        "Successfully removed Run Script phase '\(phaseName)' from target '\(targetName)'",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove run script phase: \(error.localizedDescription)",
            )
        }
    }
}
