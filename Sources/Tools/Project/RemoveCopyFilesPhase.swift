import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveCopyFilesPhase: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_copy_files_phase",
            description:
                "Remove a Copy Files build phase from a target. Locates the phase by phase_name or dst_path; if the target has exactly one Copy Files phase, that one is used.",
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
                            "Optional: name of the Copy Files phase to remove. If absent, the phase is located via dst_path or by being the target's only Copy Files phase.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: dstPath of the Copy Files phase (e.g., 'docx'). Used to locate phases that have no name.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name")
        else { throw MCPError.invalidParams("project_path and target_name are required") }

        let phaseName = arguments.getString("phase_name")
        let dstPath = arguments.getString("dst_path")

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            let copyFilesPhase = try CopyFilesPhaseLocator.locate(
                in: target,
                phaseName: phaseName,
                dstPath: dstPath,
                targetName: targetName,
            )

            guard let phaseIndex = target.buildPhases.firstIndex(where: { $0 === copyFilesPhase })
            else {
                throw MCPError.internalError(
                    "Located Copy Files phase is not attached to target '\(targetName)'",
                )
            }

            // Drop any synchronized-folder build-phase-membership routing exception sets that route
            // files into this phase. Without this, the phase object is gone but the routing set's
            // buildPhase reference dangles and the write-time reference audit rejects the save.
            let droppedRoutingSets = removeRoutingExceptionSets(
                for: copyFilesPhase, target: target, xcodeproj: xcodeproj,
            )

            // Remove build files from the phase
            if let buildFiles = copyFilesPhase.files {
                for buildFile in buildFiles { xcodeproj.pbxproj.delete(object: buildFile) }
            }

            // Remove the phase from the target
            target.buildPhases.remove(at: phaseIndex)

            // Delete the phase object
            xcodeproj.pbxproj.delete(object: copyFilesPhase)

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let label = phaseName ?? copyFilesPhase.name ?? ("dstPath=" + (dstPath ?? ""))
            let routingNote = droppedRoutingSets > 0
                ? " (also removed \(droppedRoutingSets) synchronized-folder routing exception set\(droppedRoutingSets == 1 ? "" : "s"))"
                : ""
            return CallTool.Result.text(
                "Successfully removed Copy Files phase '\(label)' from target '\(targetName)'\(routingNote)"
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Removes every `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` that routes a
    /// synchronized folder's files into `phase`, detaching each from its sync group and deleting
    /// the object. Returns the number of routing sets dropped.
    private func removeRoutingExceptionSets(
        for phase: PBXCopyFilesBuildPhase,
        target: PBXNativeTarget,
        xcodeproj: XcodeProj,
    ) -> Int {
        var dropped = 0

        for syncGroup in collectSyncGroups(for: target, in: xcodeproj) {
            guard let exceptions = syncGroup.exceptions, !exceptions.isEmpty else { continue }
            var kept: [PBXFileSystemSynchronizedExceptionSet] = []
            var toDelete: [PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet] = []

            for exception in exceptions {
                if let membership =
                    exception as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet,
                   membership.buildPhase?.uuid == phase.uuid
                {
                    toDelete.append(membership)
                } else {
                    kept.append(exception)
                }
            }
            guard !toDelete.isEmpty else { continue }
            syncGroup.exceptions = kept.isEmpty ? nil : kept

            for membership in toDelete {
                xcodeproj.pbxproj.delete(object: membership)
                dropped += 1
            }
        }
        return dropped
    }

    /// Collects the synchronized root groups visible to `target` — those attached directly to the
    /// target plus any reachable by walking the project's group tree — deduplicated by UUID.
    private func collectSyncGroups(
        for target: PBXNativeTarget,
        in xcodeproj: XcodeProj,
    ) -> [PBXFileSystemSynchronizedRootGroup] {
        var byUUID: [String: PBXFileSystemSynchronizedRootGroup] = [:]

        for group in target.fileSystemSynchronizedGroups ?? [] { byUUID[group.uuid] = group }

        if let mainGroup = try? xcodeproj.pbxproj.rootProject()?.mainGroup {
            collectSyncGroups(from: mainGroup, into: &byUUID)
        }

        return Array(byUUID.values)
    }

    private func collectSyncGroups(
        from group: PBXGroup,
        into byUUID: inout [String: PBXFileSystemSynchronizedRootGroup],
    ) {
        for child in group.children {
            if let sync = child as? PBXFileSystemSynchronizedRootGroup {
                byUUID[sync.uuid] = sync
            } else if let subgroup = child as? PBXGroup {
                collectSyncGroups(from: subgroup, into: &byUUID)
            }
        }
    }
}
