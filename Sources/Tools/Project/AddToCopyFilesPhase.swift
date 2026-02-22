import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct AddToCopyFilesPhase: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_to_copy_files_phase",
            description: "Add files to an existing Copy Files build phase",
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
                        "description": .string("Name of the Copy Files phase to add files to"),
                    ]),
                    "files": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Array of file paths to add (must already exist in project)"
                        ),
                        "items": .object([
                            "type": .string("string")
                        ]),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("phase_name"),
                    .string("files"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(phaseName) = arguments["phase_name"],
            case let .array(filesArray) = arguments["files"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, phase_name, and files are required"
            )
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
                let copyFilesPhase = target.buildPhases.compactMap({ $0 as? PBXCopyFilesBuildPhase }
                )
                .first(where: { $0.name == phaseName })
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            "Copy Files phase '\(phaseName)' not found in target '\(targetName)'"
                        )
                    ]
                )
            }

            var addedFiles: [String] = []
            var notFoundFiles: [String] = []

            for fileValue in filesArray {
                guard case let .string(filePath) = fileValue else { continue }

                // Resolve the file path
                let resolvedFilePath: String
                do {
                    resolvedFilePath = try pathUtility.resolvePath(from: filePath)
                } catch {
                    // If resolution fails, try using the path as-is for matching
                    resolvedFilePath = filePath
                }

                let relativePath =
                    pathUtility.makeRelativePath(from: resolvedFilePath) ?? resolvedFilePath
                let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent

                // Find file reference in project
                if let fileRef = xcodeproj.pbxproj.fileReferences.first(where: {
                    $0.path == relativePath || $0.path == filePath || $0.name == fileName
                        || $0.path == fileName
                }) {
                    // Check if file is already in the phase
                    let alreadyInPhase =
                        copyFilesPhase.files?.contains { buildFile in
                            if let existingRef = buildFile.file as? PBXFileReference {
                                return existingRef.uuid == fileRef.uuid
                            }
                            return false
                        } ?? false

                    if alreadyInPhase {
                        addedFiles.append("\(fileName) (already present)")
                    } else {
                        let buildFile = PBXBuildFile(file: fileRef)
                        xcodeproj.pbxproj.add(object: buildFile)
                        copyFilesPhase.files?.append(buildFile)
                        addedFiles.append(fileName)
                    }
                } else {
                    notFoundFiles.append(filePath)
                }
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            var message = "Added \(addedFiles.count) file(s) to Copy Files phase '\(phaseName)':"
            for file in addedFiles {
                message += "\n  - \(file)"
            }

            if !notFoundFiles.isEmpty {
                message += "\n\nFiles not found in project (add them first with add_file):"
                for file in notFoundFiles {
                    message += "\n  - \(file)"
                }
            }

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add files to copy files phase: \(error.localizedDescription)"
            )
        }
    }
}
