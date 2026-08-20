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
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

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
                let requirement = formatVersionRequirement(
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
                return CallTool.Result(content: [
                    .text(
                        text: "No Swift Package dependencies found in project",
                        annotations: nil,
                        _meta: nil,
                    )
                ],)
            }

            let packageList = packages.joined(separator: "\n")
            return CallTool.Result(content: [
                .text(
                    text: "Swift Package dependencies:\n\(packageList)",
                    annotations: nil,
                    _meta: nil,
                )
            ],)
        } catch {
            throw MCPError.internalError(
                "Failed to list Swift Packages in Xcode project: \(error.localizedDescription)",
            )
        }
    }

    private func formatVersionRequirement(
        _ requirement: XCRemoteSwiftPackageReference.VersionRequirement,
    ) -> String {
        switch requirement {
            case let .exact(version): "exact: \(version)"
            case let .upToNextMajorVersion(version): "from: \(version)"
            case let .upToNextMinorVersion(version): "upToNextMinor: \(version)"
            case let .range(from, to): "range: \(from) - \(to)"
            case let .branch(branch): "branch: \(branch)"
            case let .revision(revision): "revision: \(revision)"
        }
    }
}
