import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddSwiftPackageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_swift_package",
            description: "Add a Swift Package dependency to an Xcode project (remote URL or local path)",
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
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        let packageURL: String?
        if case let .string(url) = arguments["package_url"] {
            packageURL = url
        } else {
            packageURL = nil
        }

        let packagePath: String?
        if case let .string(path) = arguments["package_path"] {
            packagePath = path
        } else {
            packagePath = nil
        }

        guard packageURL != nil || packagePath != nil else {
            throw
                MCPError
                .invalidParams("Either package_url (remote) or package_path (local) is required")
        }

        if packageURL != nil, packagePath != nil {
            throw MCPError.invalidParams("Specify either package_url or package_path, not both")
        }

        let targetName: String?
        if case let .string(target) = arguments["target_name"] {
            targetName = target
        } else {
            targetName = nil
        }

        let productName: String?
        if case let .string(product) = arguments["product_name"] {
            productName = product
        } else {
            productName = nil
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            if let packageURL {
                return try addRemotePackage(
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    packageURL: packageURL,
                    requirement: arguments["requirement"],
                    targetName: targetName,
                    productName: productName,
                )
            } else {
                return try addLocalPackage(
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    packagePath: packagePath!,
                    targetName: targetName,
                    productName: productName,
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add Swift Package to Xcode project: \(error.localizedDescription)",
            )
        }
    }

    private func addRemotePackage(
        xcodeproj: XcodeProj,
        projectURL: URL,
        packageURL: String,
        requirement: Value?,
        targetName: String?,
        productName: String?,
    ) throws -> CallTool.Result {
        guard case let .string(requirementStr) = requirement else {
            throw MCPError.invalidParams("requirement is required for remote packages")
        }

        // Check if package already exists
        let existingRef: XCRemoteSwiftPackageReference?
        if let project = try xcodeproj.pbxproj.rootProject() {
            existingRef = project.remotePackages.first(where: { $0.repositoryURL == packageURL })
        } else {
            existingRef = nil
        }

        if let existingRef {
            // Package exists — if a target is specified, still link the product
            guard let targetName else {
                return CallTool.Result(
                    content: [
                        .text(
                            text: "Swift Package '\(packageURL)' already exists in project",
                            annotations: nil,
                            _meta: nil,
                        ),
                    ],
                )
            }

            try addProductToTarget(
                xcodeproj: xcodeproj,
                targetName: targetName,
                productName: productName,
                packageRef: existingRef,
            )

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(text:
                        "Swift Package '\(packageURL)' already in project; linked product '\(productName ?? "Unknown")' to target '\(targetName)'",
                        annotations: nil, _meta: nil),
                ],
            )
        }

        // Create Swift Package reference
        let packageRef = XCRemoteSwiftPackageReference(
            repositoryURL: packageURL,
            versionRequirement: parseRequirement(requirementStr),
        )
        xcodeproj.pbxproj.add(object: packageRef)

        // Add to project's package references
        if let project = try xcodeproj.pbxproj.rootProject() {
            project.remotePackages.append(packageRef)
        }

        // If target name is specified, add package product to target
        if let targetName {
            try addProductToTarget(
                xcodeproj: xcodeproj,
                targetName: targetName,
                productName: productName,
                packageRef: packageRef,
            )
        }

        // Save project
        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

        var message =
            "Successfully added Swift Package '\(packageURL)' with requirement '\(requirementStr)'"
        if let targetName {
            message += " to target '\(targetName)'"
        }

        return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }

    private func addLocalPackage(
        xcodeproj: XcodeProj,
        projectURL: URL,
        packagePath: String,
        targetName: String?,
        productName: String?,
    ) throws -> CallTool.Result {
        // Check if package already exists
        let alreadyExists: Bool
        if let project = try xcodeproj.pbxproj.rootProject() {
            alreadyExists = project.localPackages.contains(where: {
                $0.relativePath == packagePath
            })
        } else {
            alreadyExists = false
        }

        if alreadyExists {
            // Package exists — if a target is specified, still link the product
            guard let targetName else {
                return CallTool.Result(
                    content: [
                        .text(
                            text: "Local Swift Package '\(packagePath)' already exists in project",
                            annotations: nil,
                            _meta: nil,
                        ),
                    ],
                )
            }

            try addProductToTarget(
                xcodeproj: xcodeproj,
                targetName: targetName,
                productName: productName,
            )

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(text:
                        "Local Swift Package '\(packagePath)' already in project; linked product '\(productName ?? "Unknown")' to target '\(targetName)'",
                        annotations: nil, _meta: nil),
                ],
            )
        }

        // Create local package reference
        let localRef = XCLocalSwiftPackageReference(relativePath: packagePath)
        xcodeproj.pbxproj.add(object: localRef)

        // Add to project's local package references
        if let project = try xcodeproj.pbxproj.rootProject() {
            project.localPackages.append(localRef)
        }

        // If target name is specified, add package product to target
        if let targetName {
            try addProductToTarget(
                xcodeproj: xcodeproj,
                targetName: targetName,
                productName: productName,
                localPackageRef: localRef,
            )
        }

        // Save project
        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

        var message = "Successfully added local Swift Package '\(packagePath)'"
        if let targetName {
            message += " to target '\(targetName)'"
        }

        return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }

    private func addProductToTarget(
        xcodeproj: XcodeProj,
        targetName: String,
        productName: String?,
        packageRef: XCRemoteSwiftPackageReference? = nil,
        localPackageRef _: XCLocalSwiftPackageReference? = nil,
    ) throws {
        guard
            let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            })
        else {
            throw MCPError.invalidParams("Target '\(targetName)' not found in project")
        }

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
    }

    private func parseRequirement(_ requirement: String)
        -> XCRemoteSwiftPackageReference.VersionRequirement
    {
        let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("from:") {
            let version = String(trimmed.dropFirst(5)).trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            return .upToNextMajorVersion(version)
        } else if trimmed.hasPrefix("upToNextMajor:") {
            let version = String(trimmed.dropFirst(14)).trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            return .upToNextMajorVersion(version)
        } else if trimmed.hasPrefix("upToNextMinor:") {
            let version = String(trimmed.dropFirst(14)).trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            return .upToNextMinorVersion(version)
        } else if trimmed.hasPrefix("branch:") {
            let branch = String(trimmed.dropFirst(7)).trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            return .branch(branch)
        } else if trimmed.hasPrefix("revision:") {
            let revision = String(trimmed.dropFirst(9)).trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            return .revision(revision)
        } else if trimmed.hasPrefix("exact:") {
            let version = String(trimmed.dropFirst(6)).trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            return .exact(version)
        } else {
            return .exact(trimmed)
        }
    }
}
