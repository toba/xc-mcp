import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListCopyFilesPhases: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_copy_files_phases",
            description: "List all Copy Files build phases for a target",
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
                        "description": .string("Name of the target to list phases for"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(
                    content: [.text("Target '\(targetName)' not found in project")],
                )
            }

            let copyFilesPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }

            if copyFilesPhases.isEmpty {
                return CallTool.Result(
                    content: [.text("No Copy Files build phases found in target '\(targetName)'")],
                )
            }

            var output = "Copy Files Build Phases in target '\(targetName)':\n\n"

            for phase in copyFilesPhases {
                let phaseName = phase.name ?? "(unnamed)"
                let destination: String
                if let subfolder = phase.dstSubfolderSpec {
                    destination = destinationString(subfolder)
                } else if let subfolder = phase.dstSubfolder {
                    destination = subfolder.rawValue
                } else {
                    destination = "(unknown)"
                }
                let dstPath = phase.dstPath ?? ""
                let fileCount = phase.files?.count ?? 0

                output += "- \(phaseName)\n"
                output += "  Destination: \(destination)\n"
                if !dstPath.isEmpty {
                    output += "  Subpath: \(dstPath)\n"
                }
                output += "  Files: \(fileCount)\n"

                if let files = phase.files, !files.isEmpty {
                    for buildFile in files {
                        if let fileRef = buildFile.file {
                            let filePath = fileRef.path ?? fileRef.name ?? "(unknown)"
                            output += "    - \(filePath)\n"
                        }
                    }
                }
                output += "\n"
            }

            return CallTool.Result(content: [
                .text(output.trimmingCharacters(in: .whitespacesAndNewlines)),
            ])
        } catch {
            throw MCPError.internalError(
                "Failed to list copy files phases: \(error.localizedDescription)",
            )
        }
    }

    private func destinationString(_ subfolder: PBXCopyFilesBuildPhase.SubFolder) -> String {
        switch subfolder {
            case .absolutePath:
                return "Absolute Path"
            case .productsDirectory:
                return "Products Directory"
            case .wrapper:
                return "Wrapper"
            case .executables:
                return "Executables"
            case .resources:
                return "Resources"
            case .javaResources:
                return "Java Resources"
            case .frameworks:
                return "Frameworks"
            case .sharedFrameworks:
                return "Shared Frameworks"
            case .sharedSupport:
                return "Shared Support"
            case .plugins:
                return "Plugins"
            @unknown default:
                return "Unknown"
        }
    }
}
