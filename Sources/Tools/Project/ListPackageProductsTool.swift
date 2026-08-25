import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListPackageProductsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
        let projectPath = try arguments.getRequiredString("project_path")

        let targetName = arguments.getString("target_name")

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let targets: [PBXNativeTarget]

            if let targetName {
                guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                }) else {
                    return CallTool.Result.text("Target '\(targetName)' not found in project")
                }
                targets = [target]
            } else {
                targets = xcodeproj.pbxproj.nativeTargets
            }

            var sections: [String] = []

            for target in targets {
                guard let dependencies = target.packageProductDependencies,
                      !dependencies.isEmpty else { continue }

                // Collect build file products for this target's frameworks phase
                let frameworksPhase = target.buildPhases
                    .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase
                let buildFileProducts = Set(frameworksPhase?.files?.compactMap(\.product) ?? [])

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
                return CallTool.Result.text("No package product dependencies found in \(scope)")
            }

            return CallTool.Result.text(sections.joined(separator: "\n\n"))
        } catch {
            throw try error.asMCPError()
        }
    }
}
