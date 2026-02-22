import Foundation
import MCP
import XCMCPCore

public struct DiscoverProjectsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "discover_projs",
            description:
                "Discover Xcode projects (.xcodeproj) and workspaces (.xcworkspace) in a directory. Searches recursively up to a specified depth.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Directory path to search in. Defaults to the base path."
                        ),
                    ]),
                    "max_depth": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum depth to search. Defaults to 3. Use 0 for no recursion."
                        ),
                    ]),
                    "include_workspaces": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include .xcworkspace files in results. Defaults to true."
                        ),
                    ]),
                    "include_projects": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include .xcodeproj files in results. Defaults to true."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let searchPath: String
        if case let .string(value) = arguments["path"] {
            searchPath = try pathUtility.resolvePath(from: value)
        } else {
            searchPath = pathUtility.basePath
        }

        let maxDepth = arguments.getInt("max_depth") ?? 3
        let includeWorkspaces = arguments.getBool("include_workspaces", default: true)
        let includeProjects = arguments.getBool("include_projects", default: true)

        let fileManager = FileManager.default

        // Verify search path exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: searchPath, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw MCPError.invalidParams("Path does not exist or is not a directory: \(searchPath)")
        }

        var workspaces: [String] = []
        var projects: [String] = []

        /// Recursive search function
        func search(path: String, currentDepth: Int) {
            guard currentDepth <= maxDepth else { return }

            guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
                return
            }

            for item in contents {
                // Skip hidden files and common build directories
                if item.hasPrefix(".") || item == "DerivedData" || item == "build"
                    || item == "Pods"
                {
                    continue
                }

                let fullPath = "\(path)/\(item)"

                if item.hasSuffix(".xcworkspace") && includeWorkspaces {
                    // Skip Pods workspace and workspace inside .xcodeproj
                    if !item.hasPrefix("Pods") && !path.hasSuffix(".xcodeproj") {
                        workspaces.append(fullPath)
                    }
                } else if item.hasSuffix(".xcodeproj") && includeProjects {
                    projects.append(fullPath)
                } else {
                    var itemIsDir: ObjCBool = false
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &itemIsDir),
                        itemIsDir.boolValue
                    {
                        // Don't recurse into .xcodeproj or .xcworkspace bundles
                        if !item.hasSuffix(".xcodeproj") && !item.hasSuffix(".xcworkspace") {
                            search(path: fullPath, currentDepth: currentDepth + 1)
                        }
                    }
                }
            }
        }

        search(path: searchPath, currentDepth: 0)

        // Sort results for consistent output
        workspaces.sort()
        projects.sort()

        // Format output
        var output = "Discovered Xcode files in '\(searchPath)':\n\n"

        if includeWorkspaces {
            output += "Workspaces (\(workspaces.count)):\n"
            if workspaces.isEmpty {
                output += "  (none found)\n"
            } else {
                for ws in workspaces {
                    output += "  - \(ws)\n"
                }
            }
            output += "\n"
        }

        if includeProjects {
            output += "Projects (\(projects.count)):\n"
            if projects.isEmpty {
                output += "  (none found)\n"
            } else {
                for proj in projects {
                    output += "  - \(proj)\n"
                }
            }
        }

        return CallTool.Result(content: [.text(output)])
    }
}
