import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddPackageProductTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_package_product",
            description:
            "Link an existing Swift Package product to a target. Use when a package is already in the project but its product needs to be added to a different target.",
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
                            "Name of the target to link the product to",
                        ),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the Swift Package product to link (e.g., 'HTTPTypes', 'Alamofire')",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("product_name"),
                ]),
            ]),
            annotations: .mutation,
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
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target
            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                })
            else {
                throw MCPError.invalidParams("Target '\(targetName)' not found in project")
            }

            // Check if this product is already linked to the target
            if let existing = target.packageProductDependencies,
               existing.contains(where: { $0.productName == productName })
            {
                throw MCPError.invalidParams(
                    "Product '\(productName)' is already linked to target '\(targetName)'",
                )
            }

            // Find the package reference that provides this product by checking existing
            // product dependencies across all targets
            let packageRef: XCRemoteSwiftPackageReference? = xcodeproj.pbxproj.nativeTargets
                .lazy
                .compactMap(\.packageProductDependencies)
                .joined()
                .first(where: { $0.productName == productName })
                .flatMap(\.package)

            // Create the product dependency
            let productDependency = XCSwiftPackageProductDependency(
                productName: productName,
                package: packageRef,
            )
            xcodeproj.pbxproj.add(object: productDependency)

            if target.packageProductDependencies == nil {
                target.packageProductDependencies = []
            }
            target.packageProductDependencies?.append(productDependency)

            // Add a PBXBuildFile referencing the product dependency to the Frameworks build phase
            let buildFile = PBXBuildFile(product: productDependency)
            xcodeproj.pbxproj.add(object: buildFile)

            // Find or create the Frameworks build phase
            let frameworksBuildPhase: PBXFrameworksBuildPhase
            if let existingPhase = target.buildPhases.first(
                where: { $0 is PBXFrameworksBuildPhase },
            ) as? PBXFrameworksBuildPhase {
                frameworksBuildPhase = existingPhase
            } else {
                let newPhase = PBXFrameworksBuildPhase()
                xcodeproj.pbxproj.add(object: newPhase)
                target.buildPhases.append(newPhase)
                frameworksBuildPhase = newPhase
            }

            frameworksBuildPhase.files?.append(buildFile)

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            var message =
                "Linked product '\(productName)' to target '\(targetName)'"
            if packageRef == nil {
                message += " (no existing package reference found — product will resolve at build time)"
            }

            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add package product: \(error.localizedDescription)",
            )
        }
    }
}
