import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveSwiftPackageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_swift_package",
            description:
                "Remove a Swift Package dependency from an Xcode project (remote or local)",
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
                            "URL of the remote Swift Package repository to remove",
                        ),
                    ]),
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Relative path of the local Swift Package to remove (e.g., '../MyPackage')",
                        ),
                    ]),
                    "remove_from_targets": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to remove package from all targets (default: true)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let projectPath = try arguments.getRequiredString("project_path")

        let packageURL = arguments.getString("package_url")

        let packagePath = arguments.getString("package_path")

        guard packageURL != nil || packagePath != nil else {
            throw MCPError.invalidParams(
                "Either package_url (remote) or package_path (local) is required",
            )
        }

        if packageURL != nil, packagePath != nil {
            throw MCPError.invalidParams("Specify either package_url or package_path, not both")
        }

        let removeFromTargets: Bool

        if let remove = arguments.getOptionalBool("remove_from_targets") {
            removeFromTargets = remove
        } else {
            removeFromTargets = true
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let preimage = PBXProjWriter.preimage(of: Path(projectURL.path))
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            if let packageURL {
                return try removePackage(
                    references: \.remotePackages,
                    identifier: packageURL,
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    preimage: preimage,
                    removeFromTargets: removeFromTargets,
                )
            } else {
                return try removePackage(
                    references: \.localPackages,
                    identifier: packagePath!,
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    preimage: preimage,
                    removeFromTargets: removeFromTargets,
                )
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Removes one package reference and, on request, every product dependency it feeds
    ///
    /// - Parameters:
    ///   - references: The project array holding references of this kind, remote or local.
    ///   - identifier: The repository URL or relative path of the reference to remove.
    ///   - removeFromTargets: Whether to drop the product dependencies the reference feeds.
    private func removePackage<Reference: PackageReferencing>(
        references: ReferenceWritableKeyPath<PBXProject, [Reference]>,
        identifier: String,
        xcodeproj: XcodeProj,
        projectURL: URL,
        preimage: Data?,
        removeFromTargets: Bool,
    ) throws -> CallTool.Result {
        guard let project = try xcodeproj.pbxproj.rootProject() else {
            throw MCPError.internalError("Unable to access project root")
        }

        guard let packageIndex = project[keyPath: references].firstIndex(where: {
            $0.packageIdentifier == identifier
        }) else {
            return CallTool.Result.text(
                "\(Reference.capitalizedNoun) '\(identifier)' not found in project")
        }

        let packageRef = project[keyPath: references][packageIndex]

        if removeFromTargets {
            for target in xcodeproj.pbxproj.nativeTargets {
                let stale = (target.packageProductDependencies ?? []).filter(packageRef.owns)

                for dependency in stale {
                    removeBuildFiles(xcodeproj: xcodeproj, target: target, product: dependency)
                    target.packageProductDependencies?.removeAll { $0 === dependency }
                    xcodeproj.pbxproj.delete(object: dependency)
                }
            }
        } else {
            // Block-when-deps-remain: removing the package while targets still depend on its
            // products would leave each `XCSwiftPackageProductDependency.package` pointing at a
            // deleted reference — a dangling ref Xcode cannot load. Refuse and require the caller
            // to be explicit rather than silently writing a broken project.
            let usingTargets = xcodeproj.pbxproj.nativeTargets.filter { target in
                (target.packageProductDependencies ?? []).contains(where: packageRef.owns)
            }

            if !usingTargets.isEmpty {
                return CallTool.Result.text(
                    "Refusing to remove \(Reference.noun) '\(identifier)': it is still used "
                        + "by " + usingTargets.map(\.name).joined(separator: ", ")
                        + ". Re-run with remove_from_targets=true to remove those product "
                        + "dependencies too.")
            }
        }

        project[keyPath: references].remove(at: packageIndex)
        xcodeproj.pbxproj.delete(object: packageRef)

        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path), expectedPreimage: preimage)

        var message = "Successfully removed \(Reference.noun) '\(identifier)' from project"
        if removeFromTargets { message += " and all targets" }

        return CallTool.Result.text(message)
    }

    private func removeBuildFiles(
        xcodeproj: XcodeProj,
        target: PBXNativeTarget,
        product: XCSwiftPackageProductDependency,
    ) {
        for phase in target.buildPhases {
            guard let files = phase.files else { continue }
            let stale = files.filter { $0.product === product }

            for buildFile in stale {
                phase.files?.removeAll { $0 === buildFile }
                xcodeproj.pbxproj.delete(object: buildFile)
            }
        }
    }
}
