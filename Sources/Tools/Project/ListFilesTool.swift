import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListFilesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "list_files",
            description: "List all files in a specific target of an Xcode project",
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
                        "description": .string("Name of the target to list files for"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .readOnly,
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
            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { throw MCPError.invalidParams("Target '\(targetName)' not found in project") }

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

            // Get synchronized folders from both target.fileSystemSynchronizedGroups and
            // project-level PBXFileSystemSynchronizedRootGroup entries with exception sets
            // referencing this target.
            let projectRoot = projectURL.deletingLastPathComponent().path
            var syncFolders: [String] = []
            var visitedSyncGroups: Set<ObjectIdentifier> = []

            // Helper to format a sync group entry for this target. `targetOwnsSyncGroup` indicates
            // whether the target directly references this sync group via
            // fileSystemSynchronizedGroups. This changes the semantics:
            //   - true: all files compiled by default; membershipExceptions = files EXCLUDED
            //   - false: no files compiled by default; membershipExceptions = files INCLUDED
            func formatSyncGroup(
                _ syncGroup: PBXFileSystemSynchronizedRootGroup,
                targetOwnsSyncGroup: Bool,
            ) -> String? {
                guard let path = syncGroup.path else { return nil }
                // Skip if already visited
                guard visitedSyncGroups.insert(ObjectIdentifier(syncGroup)).inserted else {
                    return nil
                }

                var membershipExceptions: [String] = []

                if let exceptions = syncGroup.exceptions {
                    let targetExceptions = exceptions.compactMap {
                        $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet
                    }.filter { $0.target === target }
                    membershipExceptions = targetExceptions.flatMap {
                        $0.membershipExceptions ?? []
                    }
                }

                // Enumerate files on disk in the synchronized folder
                let folderPath: String

                if let fullPath = try? syncGroup.fullPath(sourceRoot: projectRoot) {
                    folderPath = fullPath
                } else {
                    folderPath = projectRoot + "/" + path
                }

                var diskFiles: [String] = []
                let folderURL = URL(filePath: folderPath).standardizedFileURL

                if let enumerator = FileManager.default.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles],
                ) {
                    let exceptionSet = Set(membershipExceptions)
                    let prefix = folderURL.path(percentEncoded: false)

                    for case let fileURL as URL in enumerator {
                        let isFile =
                            (try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                            .isRegularFile) ?? false
                        guard isFile else { continue }
                        // Get path relative to the sync folder
                        let filePath = fileURL.standardizedFileURL
                            .path(percentEncoded: false)
                        let relativePath: String

                        if filePath.hasPrefix(prefix) {
                            var start = filePath.index(
                                filePath.startIndex, offsetBy: prefix.count,
                            )
                            if start < filePath.endIndex, filePath[start] == "/" {
                                start = filePath.index(after: start)
                            }
                            relativePath = String(filePath[start...])
                        } else {
                            relativePath = fileURL.lastPathComponent
                        }
                        if targetOwnsSyncGroup {
                            // Target owns folder: all files included, exceptions are excluded
                            if !exceptionSet.contains(relativePath) {
                                diskFiles.append(relativePath)
                            }
                        } else {
                            // Target doesn't own folder: only exception files are included
                            if exceptionSet.contains(relativePath) {
                                diskFiles.append(relativePath)
                            }
                        }
                    }
                }

                var line = "  - \(path)"

                if !membershipExceptions.isEmpty {
                    if targetOwnsSyncGroup {
                        line +=
                            " (membership exceptions — not compiled: \(membershipExceptions.joined(separator: ", ")))"
                    } else {
                        line +=
                            " (membership exceptions — compiled as exceptions: \(membershipExceptions.joined(separator: ", ")))"
                    }
                }
                if !diskFiles.isEmpty {
                    diskFiles.sort()
                    let label = targetOwnsSyncGroup
                        ? "Compiled files"
                        : "Compiled files (via exceptions)"
                    line += "\n    \(label) (\(diskFiles.count)):\n"
                        + diskFiles.map { "      \($0)" }.joined(separator: "\n")
                }
                return line
            }

            // 1. Sync groups directly referenced by the target
            if let syncGroups = target.fileSystemSynchronizedGroups {
                for syncGroup in syncGroups {
                    if let line = formatSyncGroup(syncGroup, targetOwnsSyncGroup: true) {
                        syncFolders.append(line)
                    }
                }
            }

            // 2. Project-level sync groups associated via exception sets (target does NOT directly
            //    own these folders — membershipExceptions = included)
            for syncGroup in xcodeproj.pbxproj.fileSystemSynchronizedRootGroups {
                guard let exceptions = syncGroup.exceptions else { continue }
                let hasTargetException = exceptions.contains { exception in
                    guard let buildException =
                        exception as? PBXFileSystemSynchronizedBuildFileExceptionSet else {
                        return false
                    }
                    return buildException.target === target
                }
                if hasTargetException {
                    if let line = formatSyncGroup(syncGroup, targetOwnsSyncGroup: false) {
                        syncFolders.append(line)
                    }
                }
            }

            // Build sectioned output
            var sections: [String] = []
            if !syncFolders.isEmpty {
                sections.append("Synchronized folders:\n" + syncFolders.joined(separator: "\n"))
            }
            if !sources.isEmpty { sections.append("Sources:\n" + sources.joined(separator: "\n")) }
            if !resources.isEmpty {
                sections.append("Resources:\n" + resources.joined(separator: "\n"))
            }
            if !frameworks.isEmpty {
                sections.append("Frameworks:\n" + frameworks.joined(separator: "\n"))
            }

            let result = sections.isEmpty
                ? "No files found in target '\(targetName)'."
                : sections.joined(separator: "\n")

            return CallTool.Result(
                content: [
                    .text(
                        text: "Files in target '\(targetName)':\n\(result)",
                        annotations: nil,
                        _meta: nil,
                    )
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
