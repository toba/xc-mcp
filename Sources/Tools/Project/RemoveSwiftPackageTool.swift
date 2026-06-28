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
            throw MCPError.invalidParams(
                "Either package_url (remote) or package_path (local) is required",
            )
        }

        if packageURL != nil, packagePath != nil {
            throw MCPError.invalidParams("Specify either package_url or package_path, not both")
        }

        let removeFromTargets: Bool

        if case let .bool(remove) = arguments["remove_from_targets"] {
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
                return try removeRemotePackage(
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    preimage: preimage,
                    packageURL: packageURL,
                    removeFromTargets: removeFromTargets,
                )
            } else {
                return try removeLocalPackage(
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    preimage: preimage,
                    packagePath: packagePath!,
                    removeFromTargets: removeFromTargets,
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove Swift Package from Xcode project: \(error.localizedDescription)",
            )
        }
    }

    private func removeRemotePackage(
        xcodeproj: XcodeProj,
        projectURL: URL,
        preimage: Data?,
        packageURL: String,
        removeFromTargets: Bool,
    ) throws -> CallTool.Result {
        guard let project = try xcodeproj.pbxproj.rootProject() else {
            throw MCPError.internalError("Unable to access project root")
        }

        guard let packageIndex = project.remotePackages.firstIndex(where: {
            $0.repositoryURL == packageURL
        }) else {
            return CallTool.Result(content: [
                .text(
                    text: "Swift Package '\(packageURL)' not found in project",
                    annotations: nil,
                    _meta: nil,
                )
            ],)
        }

        let packageRef = project.remotePackages[packageIndex]

        if removeFromTargets {
            removeProductDependencies(xcodeproj: xcodeproj, packageRef: packageRef)
        } else {
            // Block-when-deps-remain: removing the package while targets still depend on its
            // products would leave each `XCSwiftPackageProductDependency.package` pointing at a
            // deleted reference — a dangling ref Xcode cannot load. Refuse and require the caller to
            // be explicit rather than silently writing a broken project.
            let usingTargets = xcodeproj.pbxproj.nativeTargets.filter { target in
                (target.packageProductDependencies ?? []).contains { $0.package === packageRef }
            }
            if !usingTargets.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text: "Refusing to remove Swift Package '\(packageURL)': it is still used "
                            + "by " + usingTargets.map(\.name).joined(separator: ", ")
                            + ". Re-run with remove_from_targets=true to remove those product "
                            + "dependencies too.",
                        annotations: nil,
                        _meta: nil,
                    )
                ],)
            }
        }

        project.remotePackages.remove(at: packageIndex)
        xcodeproj.pbxproj.delete(object: packageRef)

        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path), expectedPreimage: preimage)

        var message = "Successfully removed Swift Package '\(packageURL)' from project"
        if removeFromTargets { message += " and all targets" }

        return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }

    private func removeLocalPackage(
        xcodeproj: XcodeProj,
        projectURL: URL,
        preimage: Data?,
        packagePath: String,
        removeFromTargets: Bool,
    ) throws -> CallTool.Result {
        guard let project = try xcodeproj.pbxproj.rootProject() else {
            throw MCPError.internalError("Unable to access project root")
        }

        guard let packageIndex = project.localPackages.firstIndex(where: {
            $0.relativePath == packagePath
        }) else {
            return CallTool.Result(content: [
                .text(
                    text: "Local Swift Package '\(packagePath)' not found in project",
                    annotations: nil,
                    _meta: nil,
                )
            ],)
        }

        let localRef = project.localPackages[packageIndex]

        // Remove product dependencies from targets if requested Local packages don't have a direct
        // package ref on the product dependency, so we match by product name derived from the
        // package path
        let packageName = URL(fileURLWithPath: packagePath).lastPathComponent
        // Local package products carry no package reference, so they are matched by product name
        // (which conventionally matches the package directory name).
        func dependsOnPackage(_ dependency: XCSwiftPackageProductDependency) -> Bool {
            dependency.package == nil && dependency.productName == packageName
        }

        if removeFromTargets {
            for target in xcodeproj.pbxproj.nativeTargets {
                if let dependencies = target.packageProductDependencies {
                    for dependency in dependencies where dependsOnPackage(dependency) {
                        removeBuildFiles(xcodeproj: xcodeproj, target: target, product: dependency)
                        target.packageProductDependencies?.removeAll { $0 === dependency }
                        xcodeproj.pbxproj.delete(object: dependency)
                    }
                }
            }
        } else {
            let usingTargets = xcodeproj.pbxproj.nativeTargets.filter { target in
                (target.packageProductDependencies ?? []).contains(where: dependsOnPackage)
            }
            if !usingTargets.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text: "Refusing to remove local Swift Package '\(packagePath)': it is "
                            + "still used by " + usingTargets.map(\.name).joined(separator: ", ")
                            + ". Re-run with remove_from_targets=true to remove those product "
                            + "dependencies too.",
                        annotations: nil,
                        _meta: nil,
                    )
                ],)
            }
        }

        project.localPackages.remove(at: packageIndex)
        xcodeproj.pbxproj.delete(object: localRef)

        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path), expectedPreimage: preimage)

        var message = "Successfully removed local Swift Package '\(packagePath)' from project"
        if removeFromTargets { message += " and all targets" }

        return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }

    private func removeProductDependencies(
        xcodeproj: XcodeProj,
        packageRef: XCRemoteSwiftPackageReference,
    ) {
        for target in xcodeproj.pbxproj.nativeTargets {
            if let dependencies = target.packageProductDependencies {
                let dependenciesToRemove = dependencies.filter { dependency in
                    dependency.package === packageRef
                }

                for dependency in dependenciesToRemove {
                    removeBuildFiles(xcodeproj: xcodeproj, target: target, product: dependency)
                    target.packageProductDependencies?.removeAll { $0 === dependency }
                    xcodeproj.pbxproj.delete(object: dependency)
                }
            }
        }
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
