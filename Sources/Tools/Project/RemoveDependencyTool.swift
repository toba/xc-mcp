import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveDependencyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_dependency",
            description:
                "Remove a PBXTargetDependency edge between two targets (inverse of add_dependency). Does not modify Frameworks build phase or the dependency target itself.",
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
                        "description": .string("Name of the dependent target"),
                    ]),
                    "dependency_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the depended-on target whose PBXTargetDependency edge should be removed",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("dependency_name"),
                ]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(dependencyName) = arguments["dependency_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and dependency_name are required",
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
                    content: [
                        .text(
                            text: "Target '\(targetName)' not found in project",
                            annotations: nil,
                            _meta: nil,
                        ),
                    ],
                )
            }

            // Find matching edges: prefer match by linked target name, fall back to dep.name,
            // and finally remoteInfo on the proxy. This mirrors how add_dependency wires things up
            // (target + container proxy with remoteInfo set to the dependency target's name).
            let matches = target.dependencies.enumerated().filter { _, dep in
                if let linked = dep.target, linked.name == dependencyName { return true }
                if dep.name == dependencyName { return true }
                if dep.targetProxy?.remoteInfo == dependencyName { return true }
                return false
            }

            if matches.isEmpty {
                return CallTool.Result(
                    content: [
                        .text(
                            text:
                                "Target '\(targetName)' has no PBXTargetDependency edge to '\(dependencyName)'",
                            annotations: nil,
                            _meta: nil,
                        ),
                    ],
                )
            }

            // Remove from highest index down so earlier indices stay valid.
            let indicesToRemove = matches.map(\.offset).sorted(by: >)
            var removedDeps: [PBXTargetDependency] = []
            for idx in indicesToRemove {
                removedDeps.append(target.dependencies.remove(at: idx))
            }

            for dep in removedDeps {
                if let proxy = dep.targetProxy {
                    xcodeproj.pbxproj.delete(object: proxy)
                }
                xcodeproj.pbxproj.delete(object: dep)
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let suffix = removedDeps.count == 1 ? "" : " (\(removedDeps.count) edges)"
            return CallTool.Result(
                content: [
                    .text(
                        text:
                            "Successfully removed dependency '\(dependencyName)' from target '\(targetName)'\(suffix)",
                        annotations: nil,
                        _meta: nil,
                    ),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove dependency: \(error.localizedDescription)",
            )
        }
    }
}
