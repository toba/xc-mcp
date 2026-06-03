import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct SetCopyFilesPhaseSubpath: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "set_copy_files_phase_subpath",
            description:
            "Rename a Copy Files build phase's dstPath (subpath) in place. Locates the phase by phase_name or current dst_path; if the target has exactly one Copy Files phase, that one is used. Preserves the phase's identity, files, name, destination, and any synchronized-folder membership exception sets — unlike remove + recreate.",
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
                            "Optional: name of the Copy Files phase. If absent, the phase is located via dst_path or by being the target's only Copy Files phase.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: current dstPath of the Copy Files phase (e.g., 'docx'). Used to locate phases that have no name.",
                        ),
                    ]),
                    "new_subpath": .object([
                        "type": .string("string"),
                        "description": .string(
                            "New dstPath for the phase. Pass an empty string to clear the subpath.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("new_subpath"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(newSubpath) = arguments["new_subpath"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and new_subpath are required",
            )
        }

        let phaseName: String?
        if case let .string(p) = arguments["phase_name"] { phaseName = p } else { phaseName = nil }
        let dstPath: String?
        if case let .string(d) = arguments["dst_path"] { dstPath = d } else { dstPath = nil }

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

            let phase = try CopyFilesPhaseLocator.locate(
                in: target,
                phaseName: phaseName,
                dstPath: dstPath,
                targetName: targetName,
            )

            let oldSubpath = phase.dstPath ?? ""
            phase.dstPath = newSubpath

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let label = phase.name ?? "(unnamed)"
            let message =
                "Updated Copy Files phase '\(label)' on target '\(targetName)': dstPath '\(oldSubpath)' → '\(newSubpath)'"
            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to set copy files phase subpath: \(error.localizedDescription)",
            )
        }
    }
}
