import Foundation
import MCP
import XCMCPCore

public struct RenameSchemeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "rename_scheme",
            description: "Rename an Xcode scheme file on disk",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"
                        ),
                    ]),
                    "scheme_name": .object([
                        "type": .string("string"),
                        "description": .string("Current name of the scheme to rename"),
                    ]),
                    "new_name": .object([
                        "type": .string("string"),
                        "description": .string("New name for the scheme"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("scheme_name"), .string("new_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(schemeName) = arguments["scheme_name"],
            case let .string(newName) = arguments["new_name"]
        else {
            throw MCPError.invalidParams("project_path, scheme_name, and new_name are required")
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let fm = FileManager.default

        // Search for the scheme file in shared and user scheme directories
        let oldFilename = "\(schemeName).xcscheme"
        let newFilename = "\(newName).xcscheme"

        // Check that new name doesn't already exist
        let schemeDirs = collectSchemeDirs(projectPath: resolvedProjectPath)
        for dir in schemeDirs {
            let newPath = "\(dir)/\(newFilename)"
            if fm.fileExists(atPath: newPath) {
                return CallTool.Result(
                    content: [.text("Scheme '\(newName)' already exists")]
                )
            }
        }

        // Find and rename the scheme file
        for dir in schemeDirs {
            let oldPath = "\(dir)/\(oldFilename)"
            if fm.fileExists(atPath: oldPath) {
                let newPath = "\(dir)/\(newFilename)"
                do {
                    try fm.moveItem(atPath: oldPath, toPath: newPath)
                    return CallTool.Result(
                        content: [
                            .text(
                                "Successfully renamed scheme '\(schemeName)' to '\(newName)'"
                            )
                        ]
                    )
                } catch {
                    throw MCPError.internalError(
                        "Failed to rename scheme file: \(error.localizedDescription)"
                    )
                }
            }
        }

        return CallTool.Result(
            content: [.text("Scheme '\(schemeName)' not found in project")]
        )
    }

    private func collectSchemeDirs(projectPath: String) -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []

        let sharedDir = "\(projectPath)/xcshareddata/xcschemes"
        if fm.fileExists(atPath: sharedDir) {
            dirs.append(sharedDir)
        }

        let userdataDir = "\(projectPath)/xcuserdata"
        if let userDirs = try? fm.contentsOfDirectory(atPath: userdataDir) {
            for userDir in userDirs {
                let userSchemeDir = "\(userdataDir)/\(userDir)/xcschemes"
                if fm.fileExists(atPath: userSchemeDir) {
                    dirs.append(userSchemeDir)
                }
            }
        }

        return dirs
    }
}
