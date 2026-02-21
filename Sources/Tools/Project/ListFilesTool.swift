import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct ListFilesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_files",
            description: "List all files in a specific target of an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to list files for"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        guard case let .string(targetName) = arguments["target_name"] else {
            throw MCPError.invalidParams("target_name is required")
        }

        do {
            // Resolve and validate the path
            let resolvedPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target by name
            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                throw MCPError.invalidParams("Target '\(targetName)' not found in project")
            }

            var sources: [String] = []
            var resources: [String] = []
            var frameworks: [String] = []

            // Get files from build phases
            for buildPhase in target.buildPhases {
                if let sourcesBuildPhase = buildPhase as? PBXSourcesBuildPhase {
                    for file in sourcesBuildPhase.files ?? [] {
                        if let fileRef = file.file {
                            let name = fileRef.path ?? fileRef.name
                            if let name { sources.append("  - \(name)") }
                        }
                    }
                } else if let resourcesBuildPhase = buildPhase as? PBXResourcesBuildPhase {
                    for file in resourcesBuildPhase.files ?? [] {
                        if let fileRef = file.file {
                            let name = fileRef.path ?? fileRef.name
                            if let name { resources.append("  - \(name)") }
                        }
                    }
                } else if let frameworksBuildPhase = buildPhase as? PBXFrameworksBuildPhase {
                    for file in frameworksBuildPhase.files ?? [] {
                        if let fileRef = file.file {
                            let name = fileRef.path ?? fileRef.name
                            if let name { frameworks.append("  - \(name)") }
                        }
                    }
                }
            }

            // Get synchronized folders
            var syncFolders: [String] = []
            if let syncGroups = target.fileSystemSynchronizedGroups {
                for syncGroup in syncGroups {
                    guard let path = syncGroup.path else { continue }
                    var line = "  - \(path)"
                    // Check for per-target membership exceptions
                    if let exceptions = syncGroup.exceptions {
                        let targetExceptions = exceptions.compactMap {
                            $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet
                        }.filter { $0.target === target }
                        let excluded = targetExceptions.flatMap {
                            $0.membershipExceptions ?? []
                        }
                        if !excluded.isEmpty {
                            line += " (excludes: \(excluded.joined(separator: ", ")))"
                        }
                    }
                    syncFolders.append(line)
                }
            }

            // Build sectioned output
            var sections: [String] = []
            if !syncFolders.isEmpty {
                sections.append("Synchronized folders:\n" + syncFolders.joined(separator: "\n"))
            }
            if !sources.isEmpty {
                sections.append("Sources:\n" + sources.joined(separator: "\n"))
            }
            if !resources.isEmpty {
                sections.append("Resources:\n" + resources.joined(separator: "\n"))
            }
            if !frameworks.isEmpty {
                sections.append("Frameworks:\n" + frameworks.joined(separator: "\n"))
            }

            let result =
                sections.isEmpty
                ? "No files found in target '\(targetName)'."
                : sections.joined(separator: "\n")

            return CallTool.Result(
                content: [
                    .text("Files in target '\(targetName)':\n\(result)")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)")
        }
    }
}
