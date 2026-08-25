import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveSynchronizedFolderExceptionTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_synchronized_folder_exception",
            description:
                "Remove a file from an exception set, or remove an entire exception set from a synchronized folder. By default operates on the target's membership/exclusion exception set (PBXFileSystemSynchronizedBuildFileExceptionSet). Pass phase_name or dst_path to instead operate on the build-phase routing set (PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet) that routes the folder's files into that build phase.",
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
                            "Path of the synchronized folder within the project (e.g., 'Sources' or 'App/Sources')",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target whose exception set to modify or remove",
                        ),
                    ]),
                    "file_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: specific file to remove from the exception set. If omitted, the entire exception set is removed.",
                        ),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: name of the build phase whose routing exception set to operate on. Presence of this or dst_path switches the tool to routing-set mode.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: dstPath of the target Copy Files phase whose routing exception set to operate on (e.g., 'docx'). Used to locate an unnamed phase. Presence of this or phase_name switches the tool to routing-set mode.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("folder_path"),
                    .string("target_name"),
                ]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let folderPath = arguments.getString("folder_path"),
              let targetName = arguments.getString("target_name")
        else {
            throw MCPError.invalidParams("project_path, folder_path, and target_name are required")
        }

        let fileName = arguments.getString("file_name")
        let phaseName = arguments.getString("phase_name")
        let dstPath = arguments.getString("dst_path")

        // Presence of phase_name or dst_path switches to the build-phase routing set.
        let routingMode = phaseName != nil || dstPath != nil

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            guard let resolvedTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { throw MCPError.invalidParams("Target '\(targetName)' not found in project") }

            let syncGroup = try SynchronizedFolderUtility.resolveSyncGroup(
                folderPath: folderPath, target: resolvedTarget, in: mainGroup,
            )

            // Resolve the exception set to operate on, along with its membership list and a
            // human-readable label. Routing sets (keyed by build phase) and exclusion sets (keyed
            // by target) both carry `membershipExceptions` and are both referenced from the sync
            // group's `exceptions` array, so all downstream edits are shared.
            let exceptionUUID: String
            let membership: [String]
            let setLabel: String

            if routingMode {
                let phase = try CopyFilesPhaseLocator.locateAnyPhase(
                    in: resolvedTarget, phaseName: phaseName, dstPath: dstPath,
                    targetName: targetName,
                )
                let routingSet = syncGroup.exceptions?
                    .compactMap {
                        $0 as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet
                    }
                    .first { $0.buildPhase?.uuid == phase.uuid }
                guard let routingSet else {
                    let phaseLabel = phase.name() ?? "<unnamed phase>"
                    throw MCPError.invalidParams(
                        "No build-phase routing exception set found for phase '\(phaseLabel)' on synchronized folder '\(folderPath)'",
                    )
                }
                exceptionUUID = routingSet.uuid
                membership = routingSet.membershipExceptions ?? []
                setLabel = "routing exception set for phase '\(phase.name() ?? "<unnamed phase>")'"
            } else {
                // Find the exception set for this target on this sync group
                let exceptionSet = findExceptionSet(
                    syncGroup: syncGroup, target: resolvedTarget,
                    targetName: targetName, pbxproj: xcodeproj.pbxproj,
                )
                guard let exceptionSet else {
                    throw MCPError.invalidParams(
                        "No exception set found for target '\(targetName)' on synchronized folder '\(folderPath)'",
                    )
                }
                exceptionUUID = exceptionSet.uuid
                membership = exceptionSet.membershipExceptions ?? []
                setLabel = "exception set for target '\(targetName)'"
            }

            let syncGroupUUID = syncGroup.uuid

            // Read the raw pbxproj text — all edits happen here
            var editor = try PBXProjEditor(PBXProjTextEditor.read(projectPath: projectURL.path))

            if let fileName {
                guard membership.contains(fileName) else {
                    throw MCPError.invalidParams("File '\(fileName)' not found in \(setLabel)")
                }

                let remaining = try editor.removeEntriesFromArray(
                    blockUUID: exceptionUUID,
                    field: "membershipExceptions",
                    entries: [fileName],
                )

                if remaining == 0 {
                    // Exception set is empty — remove the block and its reference
                    try editor.removeBlock(uuid: exceptionUUID)
                    try editor.removeReference(
                        blockUUID: syncGroupUUID,
                        field: "exceptions", refUUID: exceptionUUID,
                    )

                    try PBXProjTextEditor.write(editor.text, projectPath: projectURL.path)
                    return CallTool.Result.text(
                        "Removed '\(fileName)' from \(setLabel) on '\(folderPath)'. Exception set was empty and has been removed."
                    )
                }

                try PBXProjTextEditor.write(editor.text, projectPath: projectURL.path)
                return CallTool.Result.text(
                    "Removed '\(fileName)' from \(setLabel) on '\(folderPath)'")
            } else {
                // Remove the entire exception set
                try editor.removeBlock(uuid: exceptionUUID)
                try editor.removeReference(
                    blockUUID: syncGroupUUID,
                    field: "exceptions", refUUID: exceptionUUID,
                )

                try PBXProjTextEditor.write(editor.text, projectPath: projectURL.path)
                return CallTool.Result.text(
                    "Removed \(setLabel) from synchronized folder '\(folderPath)'")
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Find the exception set for a target on a sync group. Uses identity match first, then falls
    /// back to name/UUID match.
    private func findExceptionSet(
        syncGroup: PBXFileSystemSynchronizedRootGroup,
        target: PBXNativeTarget,
        targetName: String,
        pbxproj: PBXProj,
    ) -> PBXFileSystemSynchronizedBuildFileExceptionSet? {
        // Primary: from the sync group's resolved exceptions
        if let match = syncGroup.exceptions?.first(where: {
            guard let ex = $0
                as? PBXFileSystemSynchronizedBuildFileExceptionSet
            else { return false }
            return ex.target === target || ex.target?.name == targetName
        }) as? PBXFileSystemSynchronizedBuildFileExceptionSet { return match }

        // Fallback: search all exception sets by target UUID
        return pbxproj.fileSystemSynchronizedBuildFileExceptionSets
            .first { ex in
                ex.target === target || ex.target?.name == targetName
                    || ex.target?.uuid == target.uuid
            }
    }
}
