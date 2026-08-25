import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Removes a single entry from a Copy Files build phase, leaving the phase and its other entries in
/// place.
public struct RemoveFromCopyFilesPhase: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_from_copy_files_phase",
            description:
                "Remove one entry from a Copy Files build phase without dropping the phase. Locates the phase by phase_name or dst_path, or uses the target's only Copy Files phase. Matches the entry by file name, full path, or Swift package product name. The file reference itself stays in the project; only the phase entry goes. Use remove_copy_files_phase to remove the whole phase.",
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
                    "file_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the entry to remove, e.g. 'GRDB.framework'. Matched against the entry's file name, its path, the last path component of its path, and the product name for a Swift package product.",
                        ),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: name of the Copy Files phase, e.g. 'Embed Frameworks'. If absent, the phase is located via dst_path or by being the target's only Copy Files phase.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: dstPath of the Copy Files phase (e.g. 'docx'). Used to locate phases that have no name.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("file_name"),
                ]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let fileName = arguments.getString("file_name")
        else {
            throw MCPError.invalidParams("project_path, target_name, and file_name are required")
        }

        let phaseName = arguments.getString("phase_name")
        let dstPath = arguments.getString("dst_path")

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
                in: target, phaseName: phaseName, dstPath: dstPath, targetName: targetName,
            )
            let phaseLabel = phase.name ?? ("dstPath=" + (phase.dstPath ?? ""))

            let entries = phase.files ?? []
            let matching = entries.filter { Self.matches($0, name: fileName) }

            if matching.isEmpty {
                let present = entries.map { "  - " + Self.label(for: $0) }
                let listing = present.isEmpty
                    ? "The phase is empty."
                    : "Entries in the phase:\n\(present.joined(separator: "\n"))"
                return .text(
                    "'\(fileName)' is not in Copy Files phase '\(phaseLabel)' of target '\(targetName)'. \(listing)",
                )
            }

            let removedLabels = matching.map { Self.label(for: $0) }
            let doomed = Set(matching.map(\.uuid))
            phase.files?.removeAll { doomed.contains($0.uuid) }
            for buildFile in matching { xcodeproj.pbxproj.delete(object: buildFile) }

            try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)

            let removedCount = removedLabels.count
            let noun = removedCount == 1 ? "entry" : "entries"
            let remaining = phase.files?.count ?? 0
            return .text(
                "Removed \(removedCount) \(noun) (\(removedLabels.joined(separator: ", "))) from Copy Files phase '\(phaseLabel)' of target '\(targetName)'. \(remaining) entr\(remaining == 1 ? "y" : "ies") remain.",
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    private static func matches(_ buildFile: PBXBuildFile, name: String) -> Bool {
        if let product = buildFile.product, product.productName == name { return true }
        guard let file = buildFile.file else { return false }
        if file.name == name { return true }
        guard let path = file.path else { return false }
        return path == name || (path as NSString).lastPathComponent == name
    }

    private static func label(for buildFile: PBXBuildFile) -> String {
        if let product = buildFile.product { return product.productName }
        if let file = buildFile.file { return file.path ?? file.name ?? file.uuid }
        return "<dangling \(buildFile.uuid)>"
    }
}
