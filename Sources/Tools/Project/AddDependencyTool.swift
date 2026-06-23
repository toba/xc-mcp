import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddDependencyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_dependency",
            description: "Add dependency between targets",
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
                            "Name of the target that will depend on another target",
                        ),
                    ]),
                    "dependency_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to depend on"),
                    ]),
                    "cross_project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional path (absolute or relative to project_path's directory, or a suffix like 'GRDB/GRDBCustom.xcodeproj') of a sub-project already referenced by project_path's projectReferences. Use to disambiguate when multiple referenced sub-projects expose a target named dependency_name. When dependency_name is not found among the consumer project's own native targets, add_dependency will auto-scan projectReferences for a matching target; this argument restricts the scan to one sub-project.",
                        ),
                    ]),
                    "link_binary": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Also add the dependency's product to target_name's Link Binary With Libraries phase. Defaults to false. Set true for framework/library dependencies that target_name links against (the common case). Re-running with link_binary=true links a dependency that was previously added without a Link Binary entry. Only supported for in-project dependencies; for cross-project, use add_framework.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("dependency_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(dependencyName) = arguments["dependency_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and dependency_name are required",
            )
        }

        var crossProjectPath: String?
        if case let .string(value) = arguments["cross_project_path"], !value.isEmpty {
            crossProjectPath = value
        }

        let linkBinary = arguments.getBool("link_binary")

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let sourceRoot = Path(projectURL.deletingLastPathComponent().path)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { return .text("Target '\(targetName)' not found in project") }

            // First try in-project dependency.
            if let dependencyTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == dependencyName
            }) {
                return try addInProjectDependency(
                    xcodeproj: xcodeproj,
                    projectURL: projectURL,
                    target: target,
                    targetName: targetName,
                    dependencyTarget: dependencyTarget,
                    dependencyName: dependencyName,
                    linkBinary: linkBinary,
                )
            }

            // Fall back to cross-project: scan projectReferences for a sub-project containing a
            // native target named dependencyName.
            let candidates = try findCrossProjectCandidates(
                xcodeproj: xcodeproj,
                sourceRoot: sourceRoot,
                dependencyName: dependencyName,
                crossProjectPath: crossProjectPath,
            )

            if candidates.isEmpty {
                let hint = crossProjectPath.map { " (cross_project_path='\($0)')" } ?? ""
                return .text(
                    "Dependency target '\(dependencyName)' not found in project nor in any referenced sub-project\(hint)",
                )
            }

            if candidates.count > 1 {
                let list = candidates.map { "  - \($0.absolutePath)" }.joined(separator: "\n")
                return .text(
                    "Dependency target '\(dependencyName)' is exposed by multiple referenced sub-projects. Disambiguate with cross_project_path:\n\(list)",
                )
            }

            let match = candidates[0]
            return try addCrossProjectDependency(
                xcodeproj: xcodeproj,
                projectURL: projectURL,
                target: target,
                targetName: targetName,
                dependencyName: dependencyName,
                projectRef: match.projectRef,
                remoteTargetUUID: match.remoteTargetUUID,
                linkBinary: linkBinary,
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add dependency to Xcode project: \(error.localizedDescription)",
            )
        }
    }

    private func addInProjectDependency(
        xcodeproj: XcodeProj,
        projectURL: URL,
        target: PBXNativeTarget,
        targetName: String,
        dependencyTarget: PBXNativeTarget,
        dependencyName: String,
        linkBinary: Bool,
    ) throws -> CallTool.Result {
        var didAddDependency = false

        if !target.dependencies.contains(where: { $0.target == dependencyTarget }) {
            let containerItemProxy = PBXContainerItemProxy(
                containerPortal: .project(xcodeproj.pbxproj.rootObject!),
                remoteGlobalID: .object(dependencyTarget),
                proxyType: .nativeTarget,
                remoteInfo: dependencyName,
            )
            xcodeproj.pbxproj.add(object: containerItemProxy)

            let targetDependency = PBXTargetDependency(
                name: dependencyName,
                target: dependencyTarget,
                targetProxy: containerItemProxy,
            )
            xcodeproj.pbxproj.add(object: targetDependency)

            target.dependencies.append(targetDependency)
            didAddDependency = true
        }

        var linkNote = ""
        var didLink = false

        if linkBinary {
            if let product = dependencyTarget.product {
                didLink = linkProduct(product, into: target, xcodeproj: xcodeproj)
            } else {
                linkNote = "; cannot link '\(dependencyName)' (it produces no linkable product)"
            }
        }

        // Nothing to write when the dependency already existed and no new link was added.
        if !didAddDependency, !didLink, linkNote.isEmpty {
            return .text("Target '\(targetName)' already depends on '\(dependencyName)'")
        }

        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

        let head = didAddDependency
            ? "Successfully added dependency '\(dependencyName)' to target '\(targetName)'"
            : "Target '\(targetName)' already depends on '\(dependencyName)'"
        let linkText: String

        if didLink {
            linkText = " and linked \(dependencyName) into Link Binary With Libraries"
        } else if linkBinary, linkNote.isEmpty {
            linkText = " (binary already linked)"
        } else {
            linkText = ""
        }
        return .text(head + linkText + linkNote)
    }

    /// Adds `product` to `target`'s Frameworks (Link Binary) phase, creating the phase if needed.
    /// Returns true when a new link was added, false when it was already present.
    private func linkProduct(
        _ product: PBXFileReference,
        into target: PBXNativeTarget,
        xcodeproj: XcodeProj,
    ) -> Bool {
        let frameworksPhase: PBXFrameworksBuildPhase

        if let existing = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase })
            as? PBXFrameworksBuildPhase
        {
            frameworksPhase = existing
        } else {
            let phase = PBXFrameworksBuildPhase()
            xcodeproj.pbxproj.add(object: phase)
            target.buildPhases.append(phase)
            frameworksPhase = phase
        }

        if frameworksPhase.files?.contains(where: { $0.file === product }) ?? false { return false }

        let buildFile = PBXBuildFile(file: product)
        xcodeproj.pbxproj.add(object: buildFile)

        if frameworksPhase.files == nil {
            frameworksPhase.files = [buildFile]
        } else {
            frameworksPhase.files?.append(buildFile)
        }
        return true
    }

    private func addCrossProjectDependency(
        xcodeproj: XcodeProj,
        projectURL: URL,
        target: PBXNativeTarget,
        targetName: String,
        dependencyName: String,
        projectRef: PBXFileReference,
        remoteTargetUUID: String,
        linkBinary: Bool,
    ) throws -> CallTool.Result {
        // Duplicate detection for cross-project: match by portal fileReference + remote UUID.
        let dependencyExists = target.dependencies.contains { dep in
            guard let proxy = dep.targetProxy else { return false }
            guard case let .fileReference(ref) = proxy.containerPortal, ref === projectRef
            else { return false }
            switch proxy.remoteGlobalID {
                case let .string(uuid): return uuid == remoteTargetUUID
                case let .object(obj): return obj.uuid == remoteTargetUUID
                case .none: return false
            }
        }
        if dependencyExists {
            return .text("Target '\(targetName)' already depends on '\(dependencyName)'")
        }

        let containerItemProxy = PBXContainerItemProxy(
            containerPortal: .fileReference(projectRef),
            remoteGlobalID: .string(remoteTargetUUID),
            proxyType: .nativeTarget,
            remoteInfo: dependencyName,
        )
        xcodeproj.pbxproj.add(object: containerItemProxy)

        let targetDependency = PBXTargetDependency(
            name: dependencyName,
            target: nil,
            targetProxy: containerItemProxy,
        )
        xcodeproj.pbxproj.add(object: targetDependency)

        target.dependencies.append(targetDependency)

        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

        let portalName = projectRef.path ?? projectRef.name ?? projectRef.uuid
        let linkNote = linkBinary
            ? " (link_binary is not supported for cross-project dependencies — use add_framework to link \(dependencyName).framework)"
            : ""
        return .text(
            "Successfully added cross-project dependency '\(dependencyName)' (in \(portalName)) to target '\(targetName)'\(linkNote)",
        )
    }

    private struct CrossProjectCandidate {
        let projectRef: PBXFileReference
        let absolutePath: String
        let remoteTargetUUID: String
    }

    private func findCrossProjectCandidates(
        xcodeproj: XcodeProj,
        sourceRoot: Path,
        dependencyName: String,
        crossProjectPath: String?,
    ) throws -> [CrossProjectCandidate] {
        guard let rootObject = xcodeproj.pbxproj.rootObject else { return [] }

        // Normalize a user-supplied disambiguation path: accept absolute paths, paths relative to
        // the consumer project's source root, or trailing-component matches.
        let normalizedFilter: String? = crossProjectPath.flatMap { raw in
            raw.hasPrefix("/")
                ? URL(fileURLWithPath: raw).standardizedFileURL.path
                : (sourceRoot + Path(raw)).absolute().string
        }

        var candidates: [CrossProjectCandidate] = []

        for entry in rootObject.projects {
            guard let projectRef = entry["ProjectRef"] as? PBXFileReference else { continue }
            guard let absPath = try projectRef.fullPath(sourceRoot: sourceRoot)?.absolute().string
            else { continue }

            if let filter = normalizedFilter, let rawFilter = crossProjectPath {
                // Match either by absolute-path equality (when caller gave a full/relative path
                // that resolves) or by trailing-component match (when caller gave a suffix like
                // 'GRDB/GRDBCustom.xcodeproj').
                let absMatch = absPath == filter
                let suffixMatch = absPath.hasSuffix("/" + rawFilter) || absPath.hasSuffix(rawFilter)
                if !absMatch, !suffixMatch { continue }
            }

            // Open the remote project and look for a native target by name.
            let remote: XcodeProj

            do {
                remote = try XcodeProj(path: Path(absPath))
            } catch {
                // Skip references we can't read (broken paths, permissions, etc.).
                continue
            }
            guard let remoteTarget = remote.pbxproj.nativeTargets.first(where: {
                $0.name == dependencyName
            }) else { continue }

            candidates.append(CrossProjectCandidate(
                projectRef: projectRef, absolutePath: absPath, remoteTargetUUID: remoteTarget.uuid,
            ))
        }
        return candidates
    }
}

private extension CallTool.Result {
    static func text(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }
}
