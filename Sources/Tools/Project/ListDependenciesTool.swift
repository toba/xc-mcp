import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListDependenciesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "list_dependencies",
            description:
                "List PBXTargetDependency edges for a target (the 'Target Dependencies' section of the General tab)",
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
                        "description": .string("Name of the target whose dependencies to list"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name")
        else { throw MCPError.invalidParams("project_path and target_name are required") }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            if target.dependencies.isEmpty {
                return CallTool.Result.text(
                    "Target '\(targetName)' has no PBXTargetDependency edges.")
            }

            var lines: [String] = []

            for dep in target.dependencies {
                let depName = dep.name ?? dep.target?.name ?? dep.product?.productName
                    ?? "<unnamed>"
                let proxy = dep.targetProxy
                let proxyType = proxy?.proxyType.map { String(describing: $0) } ?? "none"
                let remoteUUID: String

                switch proxy?.remoteGlobalID {
                    case let .object(obj)?: remoteUUID = obj.uuid
                    case let .string(uuid)?: remoteUUID = uuid
                    case .none: remoteUUID = "<none>"
                }
                let portal: String

                switch proxy?.containerPortal {
                    case let .project(project)?: portal = "project(\(project.uuid))"
                    case let .fileReference(ref)?:
                        portal = "fileReference(\(ref.path ?? ref.name ?? ref.uuid))"
                    case .unknownObject?: portal = "unknown"
                    case .none: portal = "<none>"
                }
                let remoteInfo = proxy?.remoteInfo ?? "<none>"
                let productPart = dep.product.map { " product=\($0.productName)" } ?? ""
                lines.append(
                    "- \(depName) [uuid=\(dep.uuid) proxyType=\(proxyType) remoteGlobalID=\(remoteUUID) remoteInfo=\(remoteInfo) containerPortal=\(portal)\(productPart)]",
                )
            }

            return CallTool.Result.text(
                "Dependencies of '\(targetName)' in \(projectURL.lastPathComponent):\n\(lines.joined(separator: "\n"))"
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
