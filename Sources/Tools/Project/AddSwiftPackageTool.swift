import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddSwiftPackageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_swift_package",
            description:
                "Add a Swift Package dependency to an Xcode project (remote URL or local path)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "package_url": .object([
                        "type": .string("string"),
                        "description": .string(
                            "URL of the Swift Package repository (for remote packages)",
                        ),
                    ]),
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Relative path to a local Swift Package directory (for local packages, e.g., '../MyPackage')",
                        ),
                    ]),
                    "requirement": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Version requirement for remote packages (e.g., '1.0.0', 'from: 1.0.0', 'branch: main'). Not used for local packages.",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Target to add the package to (optional)"),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string("Specific product name to link (optional)"),
                    ]),
                ].merging(SwiftPackageTraits.schemaProperty) { _, new in new }),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let projectPath = try arguments.getRequiredString("project_path")

        let packageURL = arguments.getString("package_url")

        let packagePath = arguments.getString("package_path")

        guard packageURL != nil || packagePath != nil else {
            throw MCPError
                .invalidParams("Either package_url (remote) or package_path (local) is required")
        }

        if packageURL != nil, packagePath != nil {
            throw MCPError.invalidParams("Specify either package_url or package_path, not both")
        }

        let targetName = arguments.getString("target_name")

        let productName = arguments.getString("product_name")

        let traits = SwiftPackageTraits.parse(from: arguments)

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            if let packageURL {
                guard case let .string(requirementStr) = arguments["requirement"] else {
                    throw MCPError.invalidParams("requirement is required for remote packages")
                }

                return try addPackage(
                    references: \.remotePackages,
                    identifier: packageURL,
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    targetName: targetName,
                    productName: productName,
                    traits: traits,
                    addedMessage:
                        "Successfully added Swift Package '\(packageURL)' with requirement '\(requirementStr)'",
                ) {
                    XCRemoteSwiftPackageReference(
                        repositoryURL: packageURL,
                        versionRequirement: PackageRequirement.parse(requirementStr),
                        traits: SwiftPackageTraits.stored(traits),
                    )
                }
            } else {
                // The guards above prove one of the two arguments is present.
                guard let packagePath else {
                    throw MCPError.invalidParams("package_path is required for local packages")
                }

                return try addPackage(
                    references: \.localPackages,
                    identifier: packagePath,
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    targetName: targetName,
                    productName: productName,
                    traits: traits,
                    addedMessage: "Successfully added local Swift Package '\(packagePath)'",
                ) {
                    XCLocalSwiftPackageReference(
                        relativePath: packagePath,
                        traits: SwiftPackageTraits.stored(traits),
                    )
                }
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Adds one package reference to the project and links its product to a target
    ///
    /// A reference that is already present is reused. The traits argument still applies to it, and
    /// a named target still gets the product linked.
    ///
    /// - Parameters:
    ///   - references: The project array holding references of this kind.
    ///   - identifier: The repository URL or relative path that selects an existing reference.
    ///   - addedMessage: The opening of the reply, used when the reference is newly created.
    ///   - makeReference: Builds the reference, called only when the project holds none.
    private func addPackage<Reference: PackageReferencing>(
        references: ReferenceWritableKeyPath<PBXProject, [Reference]>,
        identifier: String,
        xcodeproj: XcodeProj,
        projectURL: URL,
        targetName: String?,
        productName: String?,
        traits: [String]?,
        addedMessage: String,
        makeReference: () -> Reference,
    ) throws -> CallTool.Result {
        let project = try xcodeproj.pbxproj.rootProject()
        let existingRef = project?[keyPath: references]
            .first { $0.packageIdentifier == identifier }

        if let existingRef {
            // Package exists — the traits argument still applies to the existing reference.
            var traitsNote = ""

            if let traits {
                existingRef.traits = SwiftPackageTraits.stored(traits)
                traitsNote = SwiftPackageTraits.changeDescription(traits)
            }

            // If a target is specified, still link the product
            guard let targetName else {
                if traits != nil { try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path)) }
                return CallTool.Result.text(
                    "\(Reference.capitalizedNoun) '\(identifier)' already exists in project"
                        + traitsNote)
            }

            try addProductToTarget(
                xcodeproj: xcodeproj,
                targetName: targetName,
                productName: productName,
                packageRef: existingRef as? XCRemoteSwiftPackageReference,
            )

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result.text(
                "\(Reference.capitalizedNoun) '\(identifier)' already in project; linked product '\(productName ?? "Unknown")' to target '\(targetName)'"
                    + traitsNote)
        }

        let reference = makeReference()
        xcodeproj.pbxproj.add(object: reference)
        project?[keyPath: references].append(reference)

        // If target name is specified, add package product to target
        if let targetName {
            try addProductToTarget(
                xcodeproj: xcodeproj,
                targetName: targetName,
                productName: productName,
                packageRef: reference as? XCRemoteSwiftPackageReference,
            )
        }

        // Save project
        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

        var message = addedMessage
        if let targetName { message += " to target '\(targetName)'" }
        if let traits { message += SwiftPackageTraits.changeDescription(traits) }

        return CallTool.Result.text(message)
    }

    private func addProductToTarget(
        xcodeproj: XcodeProj,
        targetName: String,
        productName: String?,
        packageRef: XCRemoteSwiftPackageReference? = nil,
    ) throws {
        guard let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
        else { throw MCPError.invalidParams("Target '\(targetName)' not found in project") }

        // Check if this product is already linked to the target
        let resolvedProductName = productName ?? "Unknown"

        if let existing = target.packageProductDependencies,
           existing.contains(where: { $0.productName == resolvedProductName })
        {
            throw MCPError.invalidParams(
                "Product '\(resolvedProductName)' is already linked to target '\(targetName)'",
            )
        }

        let productDependency = XCSwiftPackageProductDependency(
            productName: productName ?? "Unknown",
            package: packageRef,
        )
        xcodeproj.pbxproj.add(object: productDependency)

        if target.packageProductDependencies == nil { target.packageProductDependencies = [] }
        target.packageProductDependencies?.append(productDependency)

        // Add a PBXBuildFile referencing the product dependency to the Frameworks build phase
        let buildFile = PBXBuildFile(product: productDependency)
        xcodeproj.pbxproj.add(object: buildFile)

        // Find or create the Frameworks build phase
        let frameworksBuildPhase: PBXFrameworksBuildPhase

        if let existingPhase = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase })
            as? PBXFrameworksBuildPhase
        {
            frameworksBuildPhase = existingPhase
        } else {
            let newPhase = PBXFrameworksBuildPhase()
            xcodeproj.pbxproj.add(object: newPhase)
            target.buildPhases.append(newPhase)
            frameworksBuildPhase = newPhase
        }

        frameworksBuildPhase.files?.append(buildFile)
    }
}
