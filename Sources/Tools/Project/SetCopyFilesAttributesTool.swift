import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Writes the `ATTRIBUTES` list on one entry of a Copy Files build phase.
///
/// `CodeSignOnCopy` re-signs the copied file with the embedding target's identity, so the copy
/// carries the app's entitlements rather than its own. A command line tool that claims an app's
/// entitlements without a matching profile is killed before `main`, which is why reading and
/// clearing this flag matters. Xcode shows the same list as the Code Sign On Copy checkbox of the
/// phase's file list.
public struct SetCopyFilesAttributesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_copy_files_attributes",
            description:
                "Set or clear the ATTRIBUTES list on one entry of a Copy Files build phase, in place. This is Xcode's Code Sign On Copy checkbox: a flagged entry is re-signed with the embedding target's identity and entitlements. The call replaces the whole list, so restate every flag the entry keeps, and pass an empty attributes array to clear the key. The entry keeps its position in the phase, unlike remove_from_copy_files_phase followed by add_to_copy_files_phase. Read the current list with list_copy_files_phases. Accepted flags: CodeSignOnCopy, RemoveHeadersOnCopy.",
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
                        "description": .string("Name of the target holding the phase"),
                    ]),
                    "file_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the Copy Files phase entry to change, e.g. 'jig'. Matched against the entry's file name, its path, the last path component of its path, and the product name for a Swift package product.",
                        ),
                    ]),
                    "attributes": .object([
                        "type": .string("array"),
                        "description": .string(
                            "The complete flag list for the entry, e.g. ['CodeSignOnCopy']. An empty array clears the key.",
                        ),
                        "items": .object(["type": .string("string")]),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: name of the Copy Files phase, e.g. 'Embed Helpers'. If absent, the phase is located via dst_path or by being the target's only Copy Files phase.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: dstPath of the Copy Files phase. Used to locate phases that have no name.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("file_name"),
                    .string("attributes"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let fileName = arguments.getNonEmptyString("file_name"),
              let requested = arguments.getOptionalStringArray("attributes")
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, file_name, and attributes are required",
            )
        }

        let attributes = try BuildFileAttributes.normalize(
            requested,
            allowed: BuildFileAttributes.copyFiles,
            allowedList: BuildFileAttributes.copyFilesList,
        )

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectFilePath = Path(projectURL.path)

            let preimage = PBXProjWriter.preimage(of: projectFilePath)
            let xcodeproj = try XcodeProj(path: projectFilePath)

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { return .text("Target '\(targetName)' not found in project") }

            let phase = try CopyFilesPhaseLocator.locate(
                in: target,
                phaseName: arguments.getNonEmptyString("phase_name"),
                dstPath: arguments.getString("dst_path"),
                targetName: targetName,
            )
            let phaseLabel = CopyFilesPhaseLocator.label(for: phase)
            let entry: PBXBuildFile

            switch CopyFilesPhaseEntry.resolve(named: fileName, in: phase, targetName: targetName) {
                case let .found(match): entry = match
                case let .explained(text): return .text(text)
            }

            let before = BuildFileAttributes.describe(BuildFileAttributes.read(entry))
            let changed = BuildFileAttributes.write(attributes, to: entry)

            guard changed else {
                return .text(
                    "'\(fileName)' in Copy Files phase '\(phaseLabel)' of target '\(targetName)' already has ATTRIBUTES \(before). No changes made.",
                )
            }

            try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)

            let after = BuildFileAttributes.describe(attributes)
            return .text(
                "Set ATTRIBUTES on '\(fileName)' in Copy Files phase '\(phaseLabel)' of target '\(targetName)' (\(before) -> \(after))",
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
