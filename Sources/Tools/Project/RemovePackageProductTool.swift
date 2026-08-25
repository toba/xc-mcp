import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemovePackageProductTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_package_product",
            description:
                "Remove an SPM package product dependency from a target without removing the package itself",
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
                        "description": .string("Name of the target to remove the product from"),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the SPM package product to remove (e.g., 'HTTPTypes')",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("product_name"),
                ]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let productName = arguments.getString("product_name")
        else {
            throw MCPError.invalidParams("project_path, target_name, and product_name are required")
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

            guard let dependencies = target.packageProductDependencies,
                  let dependency = dependencies.first(where: { $0.productName == productName })
            else {
                return CallTool.Result.text(
                    "Product '\(productName)' not found in target '\(targetName)'")
            }

            // Remove PBXBuildFile entries referencing this product from all build phases
            for phase in target.buildPhases {
                guard let files = phase.files else { continue }
                let stale = files.filter { $0.product === dependency }

                for buildFile in stale {
                    phase.files?.removeAll { $0 === buildFile }
                    xcodeproj.pbxproj.delete(object: buildFile)
                }
            }

            // Remove from target's packageProductDependencies
            target.packageProductDependencies?.removeAll { $0 === dependency }

            // Remove PBXTargetDependency entries that reference this product (Xcode GUI creates
            // these alongside packageProductDependencies)
            let staleTargetDeps = target.dependencies.filter { $0.product === dependency }

            for targetDep in staleTargetDeps {
                target.dependencies.removeAll { $0 === targetDep }
                xcodeproj.pbxproj.delete(object: targetDep)
            }

            // Delete the dependency object if no other target references it
            let stillReferenced = xcodeproj.pbxproj.nativeTargets.contains { other in
                guard other !== target else { return false }
                return other.packageProductDependencies?.contains { $0 === dependency } == true
            }

            if !stillReferenced { xcodeproj.pbxproj.delete(object: dependency) }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result.text(
                "Removed product '\(productName)' from target '\(targetName)'")
        } catch {
            throw try error.asMCPError()
        }
    }
}
