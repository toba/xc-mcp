import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListFrameworksPhaseTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_frameworks_phase",
            description:
                "List the entries of a target's PBXFrameworksBuildPhase, classifying each as fileRef (local file), productRef (Swift package product), crossProject (PBXReferenceProxy → another project's product), or dangling (missing reference). Use this to find link-only paths that bypass PBXTargetDependency edges.",
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
                            "Name of the target whose frameworks build phase to list",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(content: [
                    .text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            let phases = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }

            if phases.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text:
                            "Target '\(targetName)' has no PBXFrameworksBuildPhase. Nothing is linked.",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            // Pre-build a map from PBXTargetDependency edges so we can mark which frameworks-phase
            // entries have a corresponding ordering edge.
            let depTargetUUIDs = Set(target.dependencies.compactMap(\.target?.uuid))

            var lines: [String] = []
            for (phaseIdx, phase) in phases.enumerated() {
                if phases.count > 1 {
                    lines.append("### Frameworks phase #\(phaseIdx + 1) (\(phase.uuid))")
                }
                let files = phase.files ?? []
                if files.isEmpty {
                    lines.append("  (empty)")
                    continue
                }
                for buildFile in files {
                    lines.append("  - \(describe(buildFile: buildFile, depTargetUUIDs: depTargetUUIDs))")
                }
            }

            return CallTool.Result(content: [
                .text(
                    text:
                        "Frameworks phase for '\(targetName)' in \(projectURL.lastPathComponent):\n\(lines.joined(separator: "\n"))",
                    annotations: nil,
                    _meta: nil,
                ),
            ])
        } catch {
            throw MCPError.internalError(
                "Failed to list frameworks phase: \(error.localizedDescription)",
            )
        }
    }

    private func describe(
        buildFile: PBXBuildFile,
        depTargetUUIDs: Set<String>,
    ) -> String {
        // SPM product: buildFile.product is XCSwiftPackageProductDependency.
        if let product = buildFile.product {
            let pkg = product.package?.name ?? product.package?.repositoryURL ?? "<unresolved>"
            return
                "\(product.productName) [kind=productRef package=\(pkg) productRef=\(product.uuid)]"
        }

        guard let fileElement = buildFile.file else {
            return "<dangling> [kind=dangling buildFile=\(buildFile.uuid)]"
        }

        // Cross-project reference: PBXReferenceProxy points at another project's PBXContainerItemProxy.
        if let proxy = fileElement as? PBXReferenceProxy {
            let name = proxy.path ?? proxy.name ?? "<unnamed>"
            let remote = proxy.remote
            let portalDesc: String
            switch remote?.containerPortal {
                case let .fileReference(ref)?:
                    portalDesc = "fileReference(\(ref.path ?? ref.name ?? ref.uuid))"
                case let .project(p)?:
                    portalDesc = "project(\(p.uuid))"
                case .unknownObject?:
                    portalDesc = "unknown"
                case .none:
                    portalDesc = "<none>"
            }
            let remoteUUID: String
            switch remote?.remoteGlobalID {
                case let .object(obj)?:
                    remoteUUID = obj.uuid
                case let .string(uuid)?:
                    remoteUUID = uuid
                case .none:
                    remoteUUID = "<none>"
            }
            let depMark = depTargetUUIDs.contains(remoteUUID) ? "" : " ⚠ no PBXTargetDependency edge"
            let remoteInfo = remote?.remoteInfo ?? "<none>"
            return
                "\(name) [kind=crossProject remoteGlobalID=\(remoteUUID) remoteInfo=\(remoteInfo) containerPortal=\(portalDesc) proxy=\(proxy.uuid)]\(depMark)"
        }

        // Plain file reference (system framework, local .framework, .a, .tbd, .dylib, etc.).
        let path = fileElement.path ?? fileElement.name ?? "<unnamed>"
        let sourceTree = fileElement.sourceTree.map { String(describing: $0) } ?? "<none>"
        return "\(path) [kind=fileRef sourceTree=\(sourceTree) fileRef=\(fileElement.uuid)]"
    }
}
