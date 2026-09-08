import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Sets a target's product name in every build configuration and on its product file reference.
///
/// The two must agree. `PRODUCT_NAME` names the binary the build produces, and the target's
/// `productReference` names the file every embed phase and every scheme points at. A target whose
/// name cannot equal its product name needs both, and so does a project repaired after a bad
/// rename.
public struct SetProductNameTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_product_name",
            description:
                "Set a target's product name, writing PRODUCT_NAME in every build configuration and the path of the target's product file reference together so the two cannot drift. The file extension comes from the existing product reference, or from the target's product type. Use this when a target's name cannot equal its product name, such as an app target named 'Jig' beside a tool target that must build a binary named 'jig'.",
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
                        "description": .string("Name of the target whose product to rename"),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Product name without an extension, e.g. 'jig'. Written to PRODUCT_NAME and used as the stem of the product file name.",
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
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let productName = arguments.getNonEmptyString("product_name")
        else {
            throw MCPError.invalidParams("project_path, target_name, and product_name are required")
        }

        guard !productName.contains("/") else {
            throw MCPError.invalidParams(
                "product_name is a name, not a path. Pass 'jig', not '\(productName)'.",
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectFilePath = Path(projectURL.path)

            let preimage = PBXProjWriter.preimage(of: projectFilePath)
            let xcodeproj = try XcodeProj(path: projectFilePath)

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { return .text("Target '\(targetName)' not found in project") }

            guard let configurations = target.buildConfigurationList?.buildConfigurations,
                  !configurations.isEmpty
            else { return .text("Target '\(targetName)' has no build configuration list") }

            var changes: [String] = []

            for config in configurations {
                let before = config.buildSettings["PRODUCT_NAME"]?.stringValue
                guard before != productName else { continue }

                config.buildSettings["PRODUCT_NAME"] = .string(productName)
                changes.append(
                    "\(config.name) PRODUCT_NAME: \(before.map { "'\($0)'" } ?? "(unset)") -> '\(productName)'",
                )
            }

            // The target's own productName field stays put. Every other tool writes the target name
            // there, and a rename would flip whatever this tool wrote.
            var note = ""

            if let product = target.product {
                let fileName = Self.productFileName(
                    productName: productName, currentPath: product.path, target: target,
                )

                if product.path != fileName {
                    changes.append(
                        "product path: \(product.path.map { "'\($0)'" } ?? "(unset)") -> '\(fileName)'",
                    )
                    product.path = fileName
                }

                // Xcode leaves the name unset and shows the path. It only sets both when they
                // differ.
                if product.name != nil, product.name != fileName {
                    changes.append("product name: '\(product.name ?? "")' -> '\(fileName)'")
                    product.name = fileName
                }
            } else {
                note = "\n\nNote: target '\(targetName)' has no product file reference, so only the build settings changed."
            }

            guard !changes.isEmpty else {
                return .text(
                    "Target '\(targetName)' already builds a product named '\(productName)'. No changes made.\(note)",
                )
            }

            try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)

            var message = "Set the product name of target '\(targetName)' to '\(productName)':"
            for change in changes { message += "\n  - \(change)" }
            return .text(message + note)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// The product's file name, keeping the extension the project already carries.
    ///
    /// - Parameters:
    ///   - productName: The new name, without an extension.
    ///   - currentPath: The product reference's current path, which supplies the extension.
    ///   - target: The target, whose product type supplies the extension when the path has none.
    private static func productFileName(
        productName: String,
        currentPath: String?,
        target: PBXNativeTarget,
    ) -> String {
        let currentExtension = currentPath.map { ($0 as NSString).pathExtension } ?? ""

        if !currentExtension.isEmpty { return "\(productName).\(currentExtension)" }

        // A path with no extension may belong to a command line tool, which has none, or to a
        // product reference that was never written. The product type settles which.
        guard currentPath == nil,
              let typeExtension = target.productType?.fileExtension,
              !typeExtension.isEmpty else { return productName }

        return "\(productName).\(typeExtension)"
    }
}
