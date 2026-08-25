import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListSwiftPackagesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "list_swift_packages",
            description: "List all Swift Package dependencies in an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ])
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let projectPath = try arguments.getRequiredString("project_path")

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject() else {
                throw MCPError.internalError("Unable to access project root")
            }

            var packages: [String] = []

            // List remote packages
            for remotePackage in project.remotePackages {
                let requirement = PackageRequirement.format(
                    remotePackage.versionRequirement ?? .exact("unknown"),
                )
                let url = remotePackage.repositoryURL ?? "unknown"
                packages.append(
                    "📦 \(url) (\(requirement))\(SwiftPackageTraits.format(remotePackage.traits))",
                )
            }

            // List local packages
            for localPackage in project.localPackages {
                packages.append(
                    "📁 \(localPackage.relativePath) (local)\(SwiftPackageTraits.format(localPackage.traits))",
                )
            }

            if packages.isEmpty {
                return CallTool.Result.text("No Swift Package dependencies found in project")
            }

            let packageList = packages.joined(separator: "\n")
            return CallTool.Result.text("Swift Package dependencies:\n\(packageList)")
        } catch {
            throw try error.asMCPError()
        }
    }
}
