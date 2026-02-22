import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListSynchronizedFolderExceptionsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_synchronized_folder_exceptions",
            description:
            "List all exception sets on a synchronized folder, showing target names and excluded files",
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
                            "Path of the synchronized folder within the project (e.g., 'Sources' or 'App/Sources')",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("folder_path"),
                ]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(folderPath) = arguments["folder_path"]
        else {
            throw MCPError.invalidParams("project_path and folder_path are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the synchronized folder
            guard let project = try xcodeproj.pbxproj.rootProject(),
                  let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            guard let syncGroup = SynchronizedFolderUtility.findSyncGroup(folderPath, in: mainGroup)
            else {
                throw MCPError.invalidParams(
                    "Synchronized folder '\(folderPath)' not found in project",
                )
            }

            let exceptions = syncGroup.exceptions ?? []

            if exceptions.isEmpty {
                return CallTool.Result(
                    content: [
                        .text(
                            "No exception sets on synchronized folder '\(folderPath)'",
                        ),
                    ],
                )
            }

            var lines: [String] = [
                "Exception sets on synchronized folder '\(folderPath)':",
                "",
            ]

            for exception in exceptions {
                guard
                    let exceptionSet = exception
                    as? PBXFileSystemSynchronizedBuildFileExceptionSet
                else {
                    lines.append("Unknown exception set type: \(type(of: exception))")
                    lines.append("")
                    continue
                }

                let targetName = exceptionSet.target?.name ?? "<unknown target>"
                lines.append("Target: \(targetName)")

                if let membershipExceptions = exceptionSet.membershipExceptions,
                   !membershipExceptions.isEmpty
                {
                    lines.append("  Membership exceptions:")
                    for file in membershipExceptions.sorted() {
                        lines.append("    - \(file)")
                    }
                }

                if let publicHeaders = exceptionSet.publicHeaders, !publicHeaders.isEmpty {
                    lines.append("  Public headers:")
                    for header in publicHeaders.sorted() {
                        lines.append("    - \(header)")
                    }
                }

                if let privateHeaders = exceptionSet.privateHeaders, !privateHeaders.isEmpty {
                    lines.append("  Private headers:")
                    for header in privateHeaders.sorted() {
                        lines.append("    - \(header)")
                    }
                }

                lines.append("")
            }

            return CallTool.Result(
                content: [.text(lines.joined(separator: "\n"))],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to list synchronized folder exceptions: \(error.localizedDescription)",
            )
        }
    }
}
