import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Changes the version requirement on a remote Swift Package already declared in a project.
///
/// `add_swift_package` refuses a package that already exists, and `remove_swift_package` unlinks the
/// product from every target. Neither raises or lowers a requirement, so a version bump previously
/// meant editing the project file by hand. This tool rewrites the requirement in place and leaves
/// every target link untouched.
public struct UpdateSwiftPackageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "update_swift_package",
            description:
                "Change the version requirement of a remote Swift Package already in an Xcode "
                + "project. Rewrites the requirement in place and leaves every target link intact. "
                + "Run resolve_packages afterwards to move the pin in Package.resolved.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(
                    [
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Path to the .xcodeproj file (relative to current directory)",
                            ),
                        ]),
                        "package_url": .object([
                            "type": .string("string"),
                            "description": .string(
                                "URL of the remote Swift Package to update. Matching ignores a "
                                    + "trailing '.git' or slash, so either URL form works.",
                            ),
                        ]),
                        "requirement": .object([
                            "type": .string("string"),
                            "description": .string(
                                "New version requirement. Accepts 'from: 1.2.0', "
                                    + "'upToNextMajor: 1.2.0', 'upToNextMinor: 1.2.0', "
                                    + "'exact: 1.2.0', 'range: 1.2.0..<2.0.0', 'branch: main', "
                                    + "'revision: <sha>', or a bare version (treated as exact).",
                            ),
                        ]),
                    ].merging(SwiftPackageTraits.schemaProperty) { _, new in new },
                ),
                "required": .array([
                    .string("project_path"), .string("package_url"), .string("requirement"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }
        guard case let .string(packageURL) = arguments["package_url"] else {
            throw MCPError.invalidParams("package_url is required")
        }
        guard case let .string(requirementText) = arguments["requirement"] else {
            throw MCPError.invalidParams("requirement is required")
        }

        let traits = SwiftPackageTraits.parse(from: arguments)

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let preimage = PBXProjWriter.preimage(of: Path(projectURL.path))
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject() else {
                throw MCPError.internalError("Unable to access project root")
            }

            let wanted = PackageResolvedParser.identity(forURL: packageURL)
            guard let packageRef = project.remotePackages.first(where: {
                PackageResolvedParser.identity(forURL: $0.repositoryURL ?? "") == wanted
            }) else {
                let declared = project.remotePackages.compactMap(\.repositoryURL)
                let list = declared.isEmpty
                    ? "(none)"
                    : declared.joined(separator: ", ")
                throw MCPError.invalidParams(
                    "Swift Package '\(packageURL)' is not declared in this project. Declared "
                        + "packages: \(list)",
                )
            }

            let previous = packageRef.versionRequirement.map(PackageRequirement.format)
                ?? "(none)"
            let updated = PackageRequirement.parse(requirementText)
            packageRef.versionRequirement = updated

            var traitsNote = ""

            if let traits {
                packageRef.traits = SwiftPackageTraits.stored(traits)
                traitsNote = SwiftPackageTraits.changeDescription(traits)
            }

            try PBXProjWriter.write(
                xcodeproj, to: Path(projectURL.path), expectedPreimage: preimage,
            )

            let linkedTargets = xcodeproj.pbxproj.nativeTargets.filter { target in
                (target.packageProductDependencies ?? []).contains { $0.package === packageRef }
            }.map(\.name)

            var message = "Updated '\(packageURL)': \(previous) → "
                + PackageRequirement.format(updated) + traitsNote
            message += linkedTargets.isEmpty
                ? "\nNo target links a product of this package."
                : "\nTarget links left intact: " + linkedTargets.sorted().joined(separator: ", ")
            message += "\n\nThe pin in Package.resolved still holds the old version. Run "
                + "resolve_packages(update: true, package_url: \"\(packageURL)\") to move it."

            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to update Swift Package requirement: \(error.localizedDescription)",
            )
        }
    }
}
