import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListPackageProductsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_package_products",
            description:
            "List SPM package product dependencies for a target or all targets in an Xcode project",
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
                        "description": .string(
                            "Name of the target to list products for (lists all targets if omitted)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        let targetName: String?
        if case let .string(name) = arguments["target_name"] {
            targetName = name
        } else {
            targetName = nil
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let targets: [PBXNativeTarget]
            if let targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    return CallTool.Result(
                        content: [.text(
                            text: "Target '\(targetName)' not found in project",
                            annotations: nil,
                            _meta: nil,
                        )],
                    )
                }
                targets = [target]
            } else {
                targets = xcodeproj.pbxproj.nativeTargets
            }

            var sections: [String] = []

            for target in targets {
                guard let dependencies = target.packageProductDependencies,
                      !dependencies.isEmpty
                else {
                    continue
                }

                // Collect build file products for this target's frameworks phase
                let frameworksPhase =
                    target.buildPhases
                        .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase
                let buildFileProducts = Set(
                    frameworksPhase?.files?.compactMap(\.product) ?? [],
                )

                var lines = ["[\(target.name)]"]
                for dep in dependencies {
                    let packageInfo: String
                    if let url = dep.package?.repositoryURL {
                        packageInfo = url
                    } else {
                        packageInfo = "local"
                    }

                    let inBuildPhase = buildFileProducts.contains { $0 === dep }
                    let buildPhaseFlag = inBuildPhase ? "" : " (not in Frameworks build phase)"

                    lines.append("  - \(dep.productName) (\(packageInfo))\(buildPhaseFlag)")
                }
                sections.append(lines.joined(separator: "\n"))
            }

            if sections.isEmpty {
                let scope = targetName.map { "target '\($0)'" } ?? "any target"
                return CallTool.Result(
                    content: [.text(
                        text: "No package product dependencies found in \(scope)",
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            }

            return CallTool.Result(
                content: [.text(
                    text: sections.joined(separator: "\n\n"),
                    annotations: nil,
                    _meta: nil,
                )],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to list package products: \(error.localizedDescription)",
            )
        }
    }
}
