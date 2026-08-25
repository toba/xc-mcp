import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddSynchronizedFolderPhaseMembershipTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_synchronized_folder_phase_membership",
            description:
                "Add files from a synchronized folder to a target's build phase via PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet. Used to opt specific files from a synced root group into a Copy Files (or other) build phase. Looks up the phase by phase_name first, then by dst_path; if the target has only one Copy Files phase, that one is used.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "folder_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path of the synchronized folder within the project (e.g., 'DefaultStyles' or 'Integrations/DocX/DefaultStyles')",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target whose build phase will receive the files",
                        ),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: name of the build phase to add membership to. If absent, the phase is located via dst_path or by being the target's only Copy Files phase.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: dstPath of the target Copy Files phase (e.g., 'docx'). Used to locate phases that have no name.",
                        ),
                    ]),
                    "files": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Array of file names (relative to the synchronized folder) to add to the build phase",
                        ),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("folder_path"),
                    .string("target_name"), .string("files"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let folderPath = arguments.getString("folder_path"),
              let targetName = arguments.getString("target_name"),
              case .array = arguments["files"]
        else {
            throw MCPError.invalidParams(
                "project_path, folder_path, target_name, and files are required",
            )
        }

        let phaseName = arguments.getString("phase_name")
        let dstPath = arguments.getString("dst_path")
        let files = arguments.getStringArray("files")

        guard !files.isEmpty else { throw MCPError.invalidParams("files array must not be empty") }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                throw MCPError.invalidParams("Target '\(targetName)' not found in project")
            }

            let syncGroup = try SynchronizedFolderUtility.resolveSyncGroup(
                folderPath: folderPath, target: target, in: mainGroup,
            )

            let phase = try CopyFilesPhaseLocator.locateAnyPhase(
                in: target,
                phaseName: phaseName,
                dstPath: dstPath,
                targetName: targetName,
            )

            // Look for an existing exception set on this sync group whose buildPhase matches the
            // resolved phase.
            let existingExceptionSet = syncGroup.exceptions?.first(where: {
                guard let ex = $0
                    as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet
                else { return false }
                return ex.buildPhase?.uuid == phase.uuid
            }) as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet

            var editor = try PBXProjEditor(PBXProjTextEditor.read(projectPath: projectURL.path))

            if let existingExceptionSet {
                let existing = Set(existingExceptionSet.membershipExceptions ?? [])
                let newFiles = files.filter { !existing.contains($0) }

                if newFiles.isEmpty {
                    return CallTool.Result.text(
                        "All specified files are already in the phase membership exception set on '\(folderPath)' for target '\(targetName)'"
                    )
                }

                try editor.addEntriesToArray(
                    blockUUID: existingExceptionSet.uuid,
                    field: "membershipExceptions", entries: newFiles,
                )
            } else {
                let newUUID = PBXProjTextEditor.generateUUID()
                let folderName = syncGroup.path ?? syncGroup.name ?? folderPath
                let phaseDisplayName = phase.name() ?? "CopyFiles"
                let phaseComment = phase.name() ?? "CopyFiles"

                try editor.insertGroupBuildPhaseMembershipExceptionSetBlock(
                    uuid: newUUID,
                    folderName: folderName,
                    phaseName: phaseDisplayName,
                    phaseUUID: phase.uuid,
                    phaseComment: phaseComment,
                    targetName: targetName,
                    membershipExceptions: files,
                )

                let comment =
                    "Exceptions for \"\(folderName)\" folder in \"\(phaseDisplayName)\" phase from \"\(targetName)\" target"
                try editor.addReference(
                    blockUUID: syncGroup.uuid, field: "exceptions",
                    refUUID: newUUID, comment: comment,
                )
            }

            try PBXProjTextEditor.write(editor.text, projectPath: projectURL.path)

            let phaseDisplay = phase.name() ?? "<unnamed phase>"
            let fileList = files.joined(separator: ", ")
            return CallTool.Result.text(
                "Successfully added [\(fileList)] from synchronized folder '\(folderPath)' to build phase '\(phaseDisplay)' on target '\(targetName)'"
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
