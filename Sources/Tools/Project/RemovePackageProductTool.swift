import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemovePackageProductTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
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
                        "description": .string(
                            "Name of the target to remove the product from",
                        ),
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
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(productName) = arguments["product_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and product_name are required",
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

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

            guard let dependencies = target.packageProductDependencies,
                  let dependency = dependencies.first(where: { $0.productName == productName })
            else {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Product '\(productName)' not found in target '\(targetName)'",
                            annotations: nil, _meta: nil),
                    ],
                )
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

            // Remove PBXTargetDependency entries that reference this product
            // (Xcode GUI creates these alongside packageProductDependencies)
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

            if !stillReferenced {
                xcodeproj.pbxproj.delete(object: dependency)
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(text:
                        "Removed product '\(productName)' from target '\(targetName)'",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove package product: \(error.localizedDescription)",
            )
        }
    }
}
