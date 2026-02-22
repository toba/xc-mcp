import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct RemoveCopyFilesPhase: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_copy_files_phase",
            description: "Remove a Copy Files build phase from a target",
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
                        "description": .string("Name of the target containing the phase"),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the Copy Files phase to remove"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("phase_name"),
                ]),
            ])
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
                    content: [.text("Target '\(targetName)' not found in project")]
                )
            }

            // Find the copy files phase by name
            guard
                let phaseIndex = target.buildPhases.firstIndex(where: { phase in
                    if let copyPhase = phase as? PBXCopyFilesBuildPhase {
                        return copyPhase.name == phaseName
                    }
                    return false
                })
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            "Copy Files phase '\(phaseName)' not found in target '\(targetName)'"
                        )
                    ]
                )
            }

            guard let copyFilesPhase = target.buildPhases[phaseIndex] as? PBXCopyFilesBuildPhase
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            "Copy Files phase '\(phaseName)' not found in target '\(targetName)'"
                        )
                    ]
                )
            }

            // Remove build files from the phase
            if let buildFiles = copyFilesPhase.files {
                for buildFile in buildFiles {
                    xcodeproj.pbxproj.delete(object: buildFile)
                }
            }

            // Remove the phase from the target
            target.buildPhases.remove(at: phaseIndex)

            // Delete the phase object
            xcodeproj.pbxproj.delete(object: copyFilesPhase)

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully removed Copy Files phase '\(phaseName)' from target '\(targetName)'"
                    )
                ]
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove copy files phase: \(error.localizedDescription)"
            )
        }
    }
}
