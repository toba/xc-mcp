import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// MCP tool for repairing common Xcode project issues after migration.
///
/// Fixes problems introduced by Xcode auto-migration (e.g., objectVersion 100):
/// - Removes build files with null file references
/// - Removes orphaned `PBXBuildFile` entries not in any build phase
/// - Reports what was fixed so the caller can verify
public struct RepairProjectTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "repair_project",
            description: """
                Repair common Xcode project issues after migration. \
                Removes null build file references, orphaned PBXBuildFile entries, \
                and other artifacts left by Xcode auto-migration.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcodeproj file"),
                    ]),
                    "dry_run": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Report what would be fixed without making changes (default: false)",
                        ),
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

        let dryRun: Bool
        if case let .bool(dry) = arguments["dry_run"] { dryRun = dry } else { dryRun = false }

        let resolvedPath: String

        do {
            resolvedPath = try pathUtility.resolvePath(from: projectPath)
        } catch {
            throw MCPError.invalidParams("Invalid project path: \(error)")
        }

        let path = Path(resolvedPath)
        let xcodeproj: XcodeProj

        do {
            xcodeproj = try XcodeProj(path: path)
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }

        var fixes = [String]()
        let pbxproj = xcodeproj.pbxproj
        let targets = pbxproj.nativeTargets

        // --- Remove null file references from build phases ---
        for target in targets {
            for phase in target.buildPhases {
                guard let files = phase.files else { continue }
                let nullFiles = files.filter { $0.file == nil && $0.product == nil }

                if !nullFiles.isEmpty {
                    let phaseName = phaseName(for: phase)
                    fixes.append(
                        "Removed \(nullFiles.count) null build file\(nullFiles.count == 1 ? "" : "s") from \(target.name)/\(phaseName)",
                    )

                    if !dryRun {
                        phase.files = files.filter { $0.file != nil || $0.product != nil }
                        for nullFile in nullFiles { pbxproj.delete(object: nullFile) }
                    }
                }
            }
        }

        // --- Remove self-referencing sub-project entries --- A projectReferences entry whose
        // ProjectRef points at this project itself (e.g. "Foo.xcodeproj" nested inside
        // Foo.xcodeproj) blocks Periphery scans with "Cannot calculate full path for file element".
        // Remove the file ref, the projectReferences entry, and its empty Products group.
        let selfRefs = SelfProjectReference.detect(in: xcodeproj, projectPath: resolvedPath)

        if !selfRefs.isEmpty {
            let names = selfRefs.map { "\"\($0)\"" }.joined(separator: ", ")
            fixes.append(
                "Removed \(selfRefs.count) self-referencing sub-project entr\(selfRefs.count == 1 ? "y" : "ies") (\(names))",
            )
            if !dryRun { SelfProjectReference.remove(from: xcodeproj, projectPath: resolvedPath) }
        }

        // --- Remove orphaned PBXBuildFile entries ---
        var referencedBuildFileIDs = Set<ObjectIdentifier>()

        for target in targets {
            for phase in target.buildPhases {
                for buildFile in phase.files ?? [] {
                    referencedBuildFileIDs.insert(ObjectIdentifier(buildFile))
                }
            }
        }
        let orphans = pbxproj.buildFiles.filter {
            !referencedBuildFileIDs.contains(ObjectIdentifier($0))
        }

        if !orphans.isEmpty {
            fixes.append(
                "Removed \(orphans.count) orphaned PBXBuildFile\(orphans.count == 1 ? "" : "s") not in any build phase",
            )
            if !dryRun { for orphan in orphans { pbxproj.delete(object: orphan) } }
        }

        // --- Remove orphaned PBXTargetDependency / PBXContainerItemProxy objects ---
        // Dependency edges no longer reachable from any target's `dependencies` array (e.g. left
        // behind when a dependent target was removed) keep pointing at the depended-on target, and
        // the safe-write referential-integrity audit then refuses to drop *that* target. Garbage-
        // collect them, plus any edge/proxy whose referenced object no longer exists.
        let allTargets = pbxproj.projects.flatMap(\.targets)
        let liveTargetRefs = Set(allTargets.map(ObjectIdentifier.init))
        let referencedDependencies = Set(
            allTargets.flatMap(\.dependencies).map(ObjectIdentifier.init),
        )

        // A dependency is orphaned if no target's `dependencies` array references it, or if the
        // target/proxy it points at is gone.
        let orphanedDependencies = pbxproj.targetDependencies.filter { dependency in
            if !referencedDependencies.contains(ObjectIdentifier(dependency)) { return true }
            if let depTarget = dependency.target,
               !liveTargetRefs.contains(ObjectIdentifier(depTarget))
            {
                return true
            }
            return false
        }

        if !orphanedDependencies.isEmpty {
            fixes.append(
                "Removed \(orphanedDependencies.count) orphaned PBXTargetDependency object\(orphanedDependencies.count == 1 ? "" : "s") not referenced by any target",
            )
            if !dryRun {
                for dependency in orphanedDependencies {
                    // Detach from any target that still lists it before deleting. The proxy it owns
                    // is left for the proxy pass below, which now sees it unreferenced and reports
                    // it as the orphan it is.
                    for target in allTargets {
                        target.dependencies.removeAll { $0 === dependency }
                    }
                    pbxproj.delete(object: dependency)
                }
            }
        }

        // Container item proxies are referenced by target dependencies (targetProxy) and by
        // reference proxies (remoteRef). Any proxy not so referenced — or whose remote object is
        // gone — is an orphan. Proxies owned by the orphaned dependencies above are excluded from
        // the live set so they fall through to here even on a dry run (nothing was deleted yet).
        let orphanedDependencyIDs = Set(orphanedDependencies.map(ObjectIdentifier.init))
        let liveProxyRefs = Set(
            pbxproj.targetDependencies
                .filter { !orphanedDependencyIDs.contains(ObjectIdentifier($0)) }
                .compactMap(\.targetProxy).map(ObjectIdentifier.init),
        ).union(
            pbxproj.referenceProxies.compactMap(\.remote).map(ObjectIdentifier.init),
        )
        let orphanedProxies = pbxproj.containerItemProxies.filter { proxy in
            if liveProxyRefs.contains(ObjectIdentifier(proxy)) {
                // Still referenced, but the object it points at may be gone.
                if case let .object(obj)? = proxy.remoteGlobalID,
                   !liveTargetRefs.contains(ObjectIdentifier(obj))
                {
                    return true
                }
                return false
            }
            return true
        }

        if !orphanedProxies.isEmpty {
            fixes.append(
                "Removed \(orphanedProxies.count) orphaned PBXContainerItemProxy object\(orphanedProxies.count == 1 ? "" : "s") not referenced by any dependency",
            )
            if !dryRun { for proxy in orphanedProxies { pbxproj.delete(object: proxy) } }
        }

        // --- Write if changes were made ---
        if !fixes.isEmpty, !dryRun {
            do {
                try PBXProjWriter.write(xcodeproj, to: path)
            } catch {
                throw MCPError.internalError(
                    "Failed to write repaired project: \(error.localizedDescription)",
                )
            }
        }

        // --- Format output ---
        var output = [String]()
        if dryRun { output.append("## Dry Run — no changes written\n") }

        if fixes.isEmpty {
            output.append("No issues found in \(resolvedPath).")
        } else {
            output.append("## Repairs\(dryRun ? " (would apply)" : "")\n")
            for fix in fixes { output.append("- \(fix)") }
            output.append("")
            output.append(
                dryRun
                    ? "\(fixes.count) fix\(fixes.count == 1 ? "" : "es") available. Run without dry_run to apply."
                    : "\(fixes.count) fix\(fixes.count == 1 ? "" : "es") applied to \(resolvedPath).",
            )
        }

        return CallTool.Result(content: [
            .text(
                text: output.joined(separator: "\n"),
                annotations: nil,
                _meta: nil,
            )
        ])
    }

    private func phaseName(for phase: PBXBuildPhase) -> String {
        if let name = phase.name() { return name }

        switch phase {
            case is PBXSourcesBuildPhase: return "Sources"
            case is PBXFrameworksBuildPhase: return "Frameworks"
            case is PBXResourcesBuildPhase: return "Resources"
            case is PBXHeadersBuildPhase: return "Headers"
            case is PBXCopyFilesBuildPhase: return "Copy Files"
            default: return "Build Phase"
        }
    }
}
