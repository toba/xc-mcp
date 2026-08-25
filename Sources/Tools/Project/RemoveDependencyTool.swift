import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveDependencyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let dependencyName = arguments.getString("dependency_name")
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and dependency_name are required",
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            // Find matching edges: prefer match by linked target name, fall back to dep.name, and
            // finally remoteInfo on the proxy. This mirrors how add_dependency wires things up
            // (target + container proxy with remoteInfo set to the dependency target's name).
            let matches = target.dependencies.enumerated().filter { _, dep in
                if let linked = dep.target, linked.name == dependencyName { return true }
                return dep.name == dependencyName
                    || dep.targetProxy?.remoteInfo == dependencyName
            }

            if matches.isEmpty {
                return CallTool.Result.text(
                    "Target '\(targetName)' has no PBXTargetDependency edge to '\(dependencyName)'")
            }

            // Remove from highest index down so earlier indices stay valid.
            let indicesToRemove = matches.map(\.offset).sorted(by: >)
            var removedDeps: [PBXTargetDependency] = []
            for idx in indicesToRemove { removedDeps.append(target.dependencies.remove(at: idx)) }

            for dep in removedDeps {
                if let proxy = dep.targetProxy { xcodeproj.pbxproj.delete(object: proxy) }
                xcodeproj.pbxproj.delete(object: dep)
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let suffix = removedDeps.count == 1 ? "" : " (\(removedDeps.count) edges)"
            return CallTool.Result.text(
                "Successfully removed dependency '\(dependencyName)' from target '\(targetName)'\(suffix)"
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
