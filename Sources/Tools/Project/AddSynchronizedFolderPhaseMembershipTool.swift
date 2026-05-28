import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddSynchronizedFolderPhaseMembershipTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
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
                        "items": .object([
                            "type": .string("string"),
                        ]),
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
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(folderPath) = arguments["folder_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .array(filesArray) = arguments["files"]
        else {
            throw MCPError.invalidParams(
                "project_path, folder_path, target_name, and files are required",
            )
        }

        let phaseName: String?
        if case let .string(p) = arguments["phase_name"] { phaseName = p } else { phaseName = nil }
        let dstPath: String?
        if case let .string(d) = arguments["dst_path"] { dstPath = d } else { dstPath = nil }

        let files = filesArray.compactMap { value -> String? in
            if case let .string(s) = value { return s }
            return nil
        }

        guard !files.isEmpty else {
            throw MCPError.invalidParams("files array must not be empty")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject(),
                  let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                })
            else {
                throw MCPError.invalidParams(
                    "Target '\(targetName)' not found in project",
                )
            }

            let syncGroup = try SynchronizedFolderUtility.resolveSyncGroup(
                folderPath: folderPath, target: target, in: mainGroup,
            )

            let phase = try locatePhase(
                in: target,
                phaseName: phaseName,
                dstPath: dstPath,
                targetName: targetName,
            )

            // Look for an existing exception set on this sync group whose buildPhase
            // matches the resolved phase.
            let existingExceptionSet =
                syncGroup.exceptions?.first(where: {
                    guard
                        let ex = $0
                        as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet
                    else { return false }
                    return ex.buildPhase?.uuid == phase.uuid
                }) as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet

            var text = try PBXProjTextEditor.read(projectPath: projectURL.path)

            if let existingExceptionSet {
                let existing = Set(existingExceptionSet.membershipExceptions ?? [])
                let newFiles = files.filter { !existing.contains($0) }
                if newFiles.isEmpty {
                    return CallTool.Result(
                        content: [
                            .text(
                                text:
                                    "All specified files are already in the phase membership exception set on '\(folderPath)' for target '\(targetName)'",
                                annotations: nil, _meta: nil),
                        ],
                    )
                }

                text = try PBXProjTextEditor.addEntriesToArray(
                    text, blockUUID: existingExceptionSet.uuid,
                    field: "membershipExceptions", entries: newFiles,
                )
            } else {
                let newUUID = PBXProjTextEditor.generateUUID()
                let folderName = syncGroup.path ?? syncGroup.name ?? folderPath
                let phaseDisplayName = phase.name() ?? "CopyFiles"
                let phaseComment = phase.name() ?? "CopyFiles"

                text = try PBXProjTextEditor.insertGroupBuildPhaseMembershipExceptionSetBlock(
                    text,
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
                text = try PBXProjTextEditor.addReference(
                    text, blockUUID: syncGroup.uuid, field: "exceptions",
                    refUUID: newUUID, comment: comment,
                )
            }

            try PBXProjTextEditor.write(text, projectPath: projectURL.path)

            let phaseDisplay = phase.name() ?? "<unnamed phase>"
            let fileList = files.joined(separator: ", ")
            return CallTool.Result(
                content: [
                    .text(
                        text:
                            "Successfully added [\(fileList)] from synchronized folder '\(folderPath)' to build phase '\(phaseDisplay)' on target '\(targetName)'",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add synchronized folder phase membership: \(error.localizedDescription)",
            )
        }
    }

    /// Locate the build phase on `target` matching the given criteria.
    /// Priority: explicit `phaseName` → `dstPath` (on Copy Files phases) →
    /// the target's sole Copy Files phase.
    private func locatePhase(
        in target: PBXNativeTarget,
        phaseName: String?,
        dstPath: String?,
        targetName: String,
    ) throws -> PBXBuildPhase {
        if let phaseName {
            let byName = target.buildPhases.first { phase in
                phase.name() == phaseName
            }
            guard let byName else {
                throw MCPError.invalidParams(
                    "Build phase named '\(phaseName)' not found on target '\(targetName)'",
                )
            }
            return byName
        }

        if let dstPath {
            let copyPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            let matches = copyPhases.filter { ($0.dstPath ?? "") == dstPath }
            switch matches.count {
                case 0:
                    throw MCPError.invalidParams(
                        "No Copy Files phase with dstPath '\(dstPath)' on target '\(targetName)'",
                    )
                case 1:
                    return matches[0]
                default:
                    throw MCPError.invalidParams(
                        "Multiple Copy Files phases on target '\(targetName)' have dstPath '\(dstPath)' — pass phase_name to disambiguate",
                    )
            }
        }

        let copyPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
        switch copyPhases.count {
            case 0:
                throw MCPError.invalidParams(
                    "Target '\(targetName)' has no Copy Files build phases. Pass phase_name to select a different phase type.",
                )
            case 1:
                return copyPhases[0]
            default:
                let names = copyPhases.map { $0.name ?? ("dstPath=" + ($0.dstPath ?? "")) }
                throw MCPError.invalidParams(
                    "Target '\(targetName)' has \(copyPhases.count) Copy Files phases: \(names.joined(separator: ", ")). Pass phase_name or dst_path to disambiguate.",
                )
        }
    }
}
