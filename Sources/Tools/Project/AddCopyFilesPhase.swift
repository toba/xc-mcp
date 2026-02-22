import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct AddCopyFilesPhase: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_copy_files_phase",
            description:
                "Create a new Copy Files build phase with a destination",
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
                        "description": .string("Name of the target to add the phase to"),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the new Copy Files phase"),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Destination folder (resources, frameworks, executables, plugins, shared_support, wrapper, products_directory)"
                        ),
                    ]),
                    "subpath": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional subpath within the destination folder"
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("phase_name"),
                    .string("destination"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(phaseName) = arguments["phase_name"],
            case let .string(destination) = arguments["destination"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, phase_name, and destination are required"
            )
        }

        let subpath: String
        if case let .string(path) = arguments["subpath"] {
            subpath = path
        } else {
            subpath = ""
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

            // Map destination string to enum
            let dstSubfolderSpec = try mapDestination(destination)

            // Check if phase with same name already exists
            let existingPhase = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
                .first { $0.name == phaseName }
            if existingPhase != nil {
                return CallTool.Result(
                    content: [
                        .text(
                            "Copy Files phase '\(phaseName)' already exists in target '\(targetName)'"
                        )
                    ]
                )
            }

            // Create copy files build phase
            let copyFilesPhase = PBXCopyFilesBuildPhase(
                dstPath: subpath,
                dstSubfolderSpec: dstSubfolderSpec,
                name: phaseName
            )
            xcodeproj.pbxproj.add(object: copyFilesPhase)
            target.buildPhases.append(copyFilesPhase)

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            var message =
                "Successfully created Copy Files phase '\(phaseName)' in target '\(targetName)'"
            message += "\nDestination: \(destination)"
            if !subpath.isEmpty {
                message += "\nSubpath: \(subpath)"
            }

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add copy files phase: \(error.localizedDescription)"
            )
        }
    }

    private func mapDestination(_ destination: String) throws -> PBXCopyFilesBuildPhase.SubFolder {
        switch destination.lowercased() {
        case "resources":
            return .resources
        case "frameworks":
            return .frameworks
        case "executables":
            return .executables
        case "plugins":
            return .plugins
        case "shared_support":
            return .sharedSupport
        case "wrapper":
            return .wrapper
        case "products_directory":
            return .productsDirectory
        default:
            throw MCPError.invalidParams(
                "Invalid destination: \(destination). Must be one of: resources, frameworks, executables, plugins, shared_support, wrapper, products_directory"
            )
        }
    }
}
