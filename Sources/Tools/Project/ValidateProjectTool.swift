import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ValidateProjectTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "validate_project",
            description: """
                Validate an Xcode project for common configuration issues. \
                Checks embed phase settings, framework link/embed consistency, \
                and target dependency completeness.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcodeproj file"),
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

        let resolvedPath: String

        do {
            resolvedPath = try pathUtility.resolvePath(from: projectPath)
        } catch {
            throw MCPError.invalidParams("Invalid project path: \(error)")
        }

        let xcodeproj: XcodeProj

        do {
            xcodeproj = try XcodeProj(path: Path(resolvedPath))
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }

        let targets = xcodeproj.pbxproj.nativeTargets
        var output = [String]()
        var totalErrors = 0
        var totalWarnings = 0

        // Build a map of target name → product name for dependency checks
        var targetProductNames = [String: String]()

        for target in targets {
            if let productName = target.productNameWithExtension() ?? target.product?.path {
                targetProductNames[target.name] = productName
            }
        }

        for target in targets {
            var diagnostics = [Diagnostic]()

            let copyFilesPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            let frameworksPhase = target.buildPhases
                .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase

            // --- Embed phase validation ---
            checkEmbedPhases(copyFilesPhases, diagnostics: &diagnostics)

            // --- Copy-files dangling references ---
            checkCopyFilesReferences(copyFilesPhases, diagnostics: &diagnostics)

            // --- Framework consistency ---
            let linkedNames = frameworkNames(from: frameworksPhase)
            let embeddedNames = embeddedFrameworkNames(from: copyFilesPhases)
            checkFrameworkConsistency(
                linked: linkedNames, embedded: embeddedNames, diagnostics: &diagnostics,
            )

            // --- Dependency completeness ---
            checkDependencyCompleteness(
                target: target, xcodeproj: xcodeproj,
                targetProductNames: targetProductNames, diagnostics: &diagnostics,
            )

            // --- Duplicate PBXTargetDependency edges ---
            checkDuplicateTargetDependencies(target: target, diagnostics: &diagnostics)

            // --- Frameworks-phase link-only paths (PBXReferenceProxy without ordering edge) ---
            checkReferenceProxyWithoutDependency(target: target, diagnostics: &diagnostics)

            // --- Null file references in build phases (common after Xcode 26 migration) ---
            checkNullBuildFileReferences(target: target, diagnostics: &diagnostics)

            // --- Summary info for this target ---
            let matchedCount = linkedNames.intersection(embeddedNames).count

            if matchedCount > 0 {
                diagnostics.append(
                    Diagnostic(
                        .info,
                        "\(matchedCount) framework\(matchedCount == 1 ? "" : "s") linked and embedded correctly",
                    ),
                )
            }

            if !diagnostics.isEmpty {
                output.append("## Target: \(target.name)\n")

                for diag in diagnostics {
                    output.append(diag.formatted)
                    if diag.severity == .error { totalErrors += 1 }
                    if diag.severity == .warning { totalWarnings += 1 }
                }
                output.append("")
            }
        }

        // --- Project-level checks ---
        var projectDiagnostics = [Diagnostic]()
        checkBuildPhaseHygiene(
            xcodeproj: xcodeproj,
            targets: targets,
            diagnostics: &projectDiagnostics,
        )
        checkInconsistentEmbedding(targets: targets, diagnostics: &projectDiagnostics)
        checkOrphanedSynchronizedFolders(
            xcodeproj: xcodeproj, targets: targets, diagnostics: &projectDiagnostics,
        )
        checkPackageProductIntegrity(
            xcodeproj: xcodeproj, targets: targets, diagnostics: &projectDiagnostics,
        )
        checkSelfProjectReferences(
            xcodeproj: xcodeproj, projectPath: resolvedPath, diagnostics: &projectDiagnostics,
        )
        checkStaleRemoteInfo(xcodeproj: xcodeproj, diagnostics: &projectDiagnostics)

        if !projectDiagnostics.isEmpty {
            output.append("## Project-level\n")

            for diag in projectDiagnostics {
                output.append(diag.formatted)
                if diag.severity == .error { totalErrors += 1 }
                if diag.severity == .warning { totalWarnings += 1 }
            }
            output.append("")
        }

        // Summary
        if totalErrors == 0, totalWarnings == 0 {
            output.append("No issues found in \(resolvedPath).")
        } else {
            var parts = [String]()
            if totalErrors > 0 {
                parts.append("\(totalErrors) error\(totalErrors == 1 ? "" : "s")")
            }
            if totalWarnings > 0 {
                parts.append("\(totalWarnings) warning\(totalWarnings == 1 ? "" : "s")")
            }
            output.append("## Summary: \(parts.joined(separator: ", "))")
        }

        return CallTool.Result(content: [
            .text(
                text: output.joined(separator: "\n"),
                annotations: nil,
                _meta: nil,
            )
        ])
    }

    // MARK: - Embed Phase Checks

    private func checkEmbedPhases(
        _ phases: [PBXCopyFilesBuildPhase],
        diagnostics: inout [Diagnostic],
    ) {
        for phase in phases {
            let phaseName = phase.name ?? "(unnamed)"

            // Check destination on phases named "Embed Frameworks"
            if phaseName.contains("Embed Frameworks"),
               phase.dstSubfolderSpec == nil,
               phase.dstSubfolder != .frameworks
            {
                diagnostics.append(Diagnostic(
                    .error,
                    "Embed phase \"\(phaseName)\" has dstSubfolder=None (should be Frameworks)",
                ))
            }

            // Empty copy-files phases
            if (phase.files ?? []).isEmpty {
                diagnostics.append(Diagnostic(
                    .warning,
                    "Copy-files phase \"\(phaseName)\" has zero files"
                ))
            }
        }

        // Duplicate framework in multiple copy-files phases
        var seenFiles = [String: String]()  // filename → first phase name

        for phase in phases {
            let phaseName = phase.name ?? "(unnamed)"

            for buildFile in phase.files ?? [] {
                guard let fileRef = buildFile.file else { continue }
                let name = fileRef.path ?? fileRef.name ?? "(unknown)"

                if let firstPhase = seenFiles[name] {
                    diagnostics.append(Diagnostic(
                        .error,
                        "\(name) appears in both \"\(firstPhase)\" and \"\(phaseName)\"",
                    ))
                } else {
                    seenFiles[name] = phaseName
                }
            }
        }
    }

    // MARK: - Framework Consistency

    private func frameworkNames(from phase: PBXFrameworksBuildPhase?) -> Set<String> {
        guard let files = phase?.files else { return [] }
        var names = Set<String>()

        for buildFile in files {
            if let fileRef = buildFile.file {
                if let name = fileRef.path ?? fileRef.name { names.insert(name) }
            }
        }
        return names
    }

    private func embeddedFrameworkNames(from phases: [PBXCopyFilesBuildPhase]) -> Set<String> {
        var names = Set<String>()

        for phase in phases
        where phase.dstSubfolderSpec == .frameworks || phase.dstSubfolder == .frameworks {
            for buildFile in phase.files ?? [] {
                if let fileRef = buildFile.file {
                    if let name = fileRef.path ?? fileRef.name { names.insert(name) }
                }
            }
        }
        return names
    }

    private func checkFrameworkConsistency(
        linked: Set<String>,
        embedded: Set<String>,
        diagnostics: inout [Diagnostic],
    ) {
        // Linked but not embedded (skip system frameworks)
        for name in linked.sorted() where !embedded.contains(name) {
            if !isSystemFramework(name) {
                diagnostics.append(Diagnostic(.warning, "\(name) linked but not embedded"))
            }
        }

        // Embedded but not linked
        for name in embedded.sorted() where !linked.contains(name) {
            diagnostics.append(Diagnostic(.warning, "\(name) embedded but not linked"))
        }
    }

    private func isSystemFramework(_ name: String) -> Bool {
        // System frameworks use .sdkRoot source tree, but at the name level we can heuristic:
        // system frameworks live under System/Library paths or are well-known SDK frameworks. For
        // this check, we skip frameworks that don't end in .framework (e.g. .tbd, .dylib) since
        // those are always system.
        !name.hasSuffix(".framework") ? true : false
    }

    // MARK: - Copy Files References

    private func checkCopyFilesReferences(
        _ phases: [PBXCopyFilesBuildPhase],
        diagnostics: inout [Diagnostic],
    ) {
        for phase in phases {
            let phaseName = phase.name ?? "(unnamed)"

            for buildFile in phase.files ?? [] where buildFile.file == nil {
                diagnostics.append(
                    Diagnostic(
                        .warning,
                        "Copy-files phase \"\(phaseName)\" contains a build file with a dangling reference",
                    ),
                )
            }
        }
    }

    // MARK: - Build Phase Hygiene

    private func checkBuildPhaseHygiene(
        xcodeproj: XcodeProj,
        targets: [PBXNativeTarget],
        diagnostics: inout [Diagnostic],
    ) {
        // Orphaned PBXBuildFile entries: in pbxproj.buildFiles but not in any build phase Use
        // ObjectIdentifier instead of Set<PBXBuildFile> to avoid XcodeProj's broken Hashable
        // conformance (buildPhase mutates after insertion).
        var referencedBuildFileIDs = Set<ObjectIdentifier>()

        for target in targets {
            for phase in target.buildPhases {
                for buildFile in phase.files ?? [] {
                    referencedBuildFileIDs.insert(ObjectIdentifier(buildFile))
                }
            }
        }
        let allBuildFiles = xcodeproj.pbxproj.buildFiles
        let orphanCount =
            allBuildFiles
            .count(where: { !referencedBuildFileIDs.contains(ObjectIdentifier($0)) })

        if orphanCount > 0 {
            diagnostics.append(
                Diagnostic(
                    .warning,
                    "\(orphanCount) orphaned PBXBuildFile\(orphanCount == 1 ? "" : "s") not referenced by any build phase",
                ),
            )
        }

        // Build phases not referenced by any target
        let targetPhases = Set(targets.flatMap(\.buildPhases).map(ObjectIdentifier.init))
        let allPhases = xcodeproj.pbxproj.buildPhases
        let unreferencedCount =
            allPhases
            .count(where: { !targetPhases.contains(ObjectIdentifier($0)) })

        if unreferencedCount > 0 {
            diagnostics.append(
                Diagnostic(
                    .info,
                    "\(unreferencedCount) build phase\(unreferencedCount == 1 ? "" : "s") not referenced by any target",
                ),
            )
        }
    }

    // MARK: - Inconsistent Embedding

    private func checkInconsistentEmbedding(
        targets: [PBXNativeTarget],
        diagnostics: inout [Diagnostic],
    ) {
        let appTargets = targets.filter { $0.productType == .application }
        guard appTargets.count > 1 else { return }

        // Collect embedded framework names per app target
        var embeddedByTarget = [String: Set<String>]()

        for target in appTargets {
            let copyFilesPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            embeddedByTarget[target.name] = embeddedFrameworkNames(from: copyFilesPhases)
        }

        // Union of all embedded frameworks
        let allEmbedded = embeddedByTarget.values.reduce(into: Set<String>()) { $0.formUnion($1) }

        for name in allEmbedded.sorted() {
            let targetsWithFramework =
                appTargets
                .filter { embeddedByTarget[$0.name]?.contains(name) == true }

            if targetsWithFramework.count < appTargets.count {
                let havingNames = targetsWithFramework.map(\.name).sorted().joined(separator: ", ")
                diagnostics.append(Diagnostic(
                    .info,
                    "\(name) embedded in \(havingNames) but not all app targets",
                ))
            }
        }
    }

    // MARK: - Null Build File References (Post-Migration)

    private func checkNullBuildFileReferences(
        target: PBXNativeTarget,
        diagnostics: inout [Diagnostic],
    ) {
        var nullCount = 0

        for phase in target.buildPhases {
            for buildFile in phase.files ?? [] where buildFile.file == nil {
                // Skip product references (e.g. SPM products) which use productRef instead
                if buildFile.product != nil { continue }
                nullCount += 1
            }
        }
        if nullCount > 0 {
            diagnostics.append(
                Diagnostic(
                    .warning,
                    "\(nullCount) build file\(nullCount == 1 ? "" : "s") with null file reference (possible Xcode migration artifact)",
                ),
            )
        }
    }

    // MARK: - Orphaned Synchronized Folders

    private func checkOrphanedSynchronizedFolders(
        xcodeproj: XcodeProj,
        targets: [PBXNativeTarget],
        diagnostics: inout [Diagnostic],
    ) {
        let allSyncGroups = xcodeproj.pbxproj.fileSystemSynchronizedRootGroups
        guard !allSyncGroups.isEmpty else { return }

        let linkedSyncGroupIDs = Set(targets.flatMap { $0.fileSystemSynchronizedGroups ?? [] }
                .map(ObjectIdentifier.init),
        )

        for group in allSyncGroups where !linkedSyncGroupIDs.contains(ObjectIdentifier(group)) {
            let name = group.path ?? group.name ?? "(unknown)"
            diagnostics.append(Diagnostic(
                .warning,
                "Synchronized folder \"\(name)\" not linked to any target",
            ))
        }
    }

    // MARK: - Package Product Integrity

    private func checkPackageProductIntegrity(
        xcodeproj _: XcodeProj,
        targets: [PBXNativeTarget],
        diagnostics: inout [Diagnostic],
    ) {
        // Collect all package product references from frameworks phases
        for target in targets {
            let frameworksPhase = target.buildPhases
                .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase
            guard let files = frameworksPhase?.files else { continue }

            for buildFile in files {
                // Build files that reference SPM products use productRef
                if let productRef = buildFile.product {
                    let productName = productRef.productName
                    // Check if the package reference still exists
                    if productRef.package == nil {
                        diagnostics.append(
                            Diagnostic(
                                .error,
                                "Package product \"\(productName)\" in target \"\(target.name)\" has no package reference (missing or broken link)",
                            ),
                        )
                    }
                }
            }
        }
    }

    // MARK: - Self-Referential Project References

    private func checkSelfProjectReferences(
        xcodeproj: XcodeProj,
        projectPath: String,
        diagnostics: inout [Diagnostic],
    ) {
        let selfRefs = SelfProjectReference.detect(in: xcodeproj, projectPath: projectPath)

        for name in selfRefs {
            diagnostics.append(
                Diagnostic(
                    .error,
                    "Self-referencing sub-project entry \"\(name)\" (the project nested inside itself) — blocks Periphery scans; run repair_project to remove",
                ),
            )
        }
    }

    // MARK: - Dependency Completeness

    private func checkDependencyCompleteness(
        target: PBXNativeTarget,
        xcodeproj _: XcodeProj,
        targetProductNames: [String: String],
        diagnostics: inout [Diagnostic],
    ) {
        let frameworksPhase = target.buildPhases
            .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase

        let linkedFiles = frameworksPhase?.files ?? []

        // Build set of dependency target names
        let dependencyTargetNames = Set(target.dependencies.compactMap { $0.target?.name })

        // Build set of product names that are linked
        let linkedProductNames = Set(linkedFiles.compactMap { $0.file?.path ?? $0.file?.name })

        // Check: target links a product from another target but has no dependency
        for (depTargetName, productName) in targetProductNames {
            if depTargetName == target.name { continue }

            if linkedProductNames.contains(productName),
               !dependencyTargetNames.contains(depTargetName)
            {
                diagnostics.append(Diagnostic(
                    .warning,
                    "Links \(productName) from \(depTargetName) but has no target dependency",
                ))
            }
        }

        // Check: target has dependency but doesn't link the product
        for dep in target.dependencies {
            guard let depTarget = dep.target else { continue }

            if let productName = targetProductNames[depTarget.name],
               !linkedProductNames.contains(productName)
            {
                diagnostics.append(Diagnostic(
                    .info,
                    "Has dependency on \(depTarget.name) but does not link \(productName)",
                ))
            }
        }
    }

    // MARK: - Duplicate Target Dependencies

    /// Flags >1 PBXTargetDependency edges from `target` that resolve to the same remote target.
    /// Xcode normally collapses these into one build-graph node, but the modern explicit-modules
    /// planner can import them as distinct nodes that collide with
    /// "Multiple targets in the build graph have the target ID …" at archive time.
    private func checkDuplicateTargetDependencies(
        target: PBXNativeTarget,
        diagnostics: inout [Diagnostic],
    ) {
        // Group dependency edges by the remote target identity. Prefer the resolved target
        // pointer, then the proxy's remoteGlobalID uuid, then the linked target uuid. This way
        // an edge with a dangling proxy still collides with a healthy edge to the same target.
        var groups: [String: [PBXTargetDependency]] = [:]
        var nameByKey: [String: String] = [:]

        for dep in target.dependencies {
            let key: String
            if let linked = dep.target {
                key = linked.uuid
                nameByKey[key] = linked.name
            } else if let remote = dep.targetProxy?.remoteGlobalID {
                switch remote {
                    case let .object(obj):
                        key = obj.uuid
                        if nameByKey[key] == nil {
                            nameByKey[key] = (obj as? PBXTarget)?.name ?? dep.name
                        }
                    case let .string(uuid):
                        key = uuid
                        if nameByKey[key] == nil { nameByKey[key] = dep.name ?? uuid }
                }
            } else {
                continue
            }
            groups[key, default: []].append(dep)
        }

        for (key, edges) in groups where edges.count > 1 {
            let name = nameByKey[key] ?? "<unknown>"
            let detail = edges.map { dep in
                let remoteInfo = dep.targetProxy?.remoteInfo ?? "<none>"
                return "\(dep.uuid) (remoteInfo=\(remoteInfo))"
            }.joined(separator: ", ")
            diagnostics.append(Diagnostic(
                .warning,
                "Duplicate PBXTargetDependency edges to \(name) (\(key)): \(edges.count) edges — \(detail). Use remove_dependency to drop the redundant edge(s).",
            ))
        }
    }

    // MARK: - Reference Proxy Without Dependency

    /// Flags PBXFrameworksBuildPhase entries that link a `PBXReferenceProxy` (cross-project
    /// product reference) without a matching PBXTargetDependency edge. The link still produces
    /// a build-graph node for the remote target, so this is the asymmetry that lets a consumer
    /// pull in a target via the frameworks phase alone — bypassing the ordering edge and, under
    /// the explicit-modules planner, sometimes creating duplicate target-ID nodes that collide
    /// with "Multiple targets in the build graph have the target ID …".
    private func checkReferenceProxyWithoutDependency(
        target: PBXNativeTarget,
        diagnostics: inout [Diagnostic],
    ) {
        let frameworksPhases = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }
        guard !frameworksPhases.isEmpty else { return }

        let depTargetUUIDs = Set(target.dependencies.compactMap(\.target?.uuid))

        for phase in frameworksPhases {
            for buildFile in phase.files ?? [] {
                guard let proxyRef = buildFile.file as? PBXReferenceProxy,
                      let remote = proxyRef.remote?.remoteGlobalID
                else { continue }

                let remoteUUID: String
                switch remote {
                    case let .object(obj): remoteUUID = obj.uuid
                    case let .string(uuid): remoteUUID = uuid
                }
                if depTargetUUIDs.contains(remoteUUID) { continue }

                let name = proxyRef.path ?? proxyRef.name ?? "<unnamed>"
                let remoteInfo = proxyRef.remote?.remoteInfo ?? "<none>"
                diagnostics.append(Diagnostic(
                    .warning,
                    "Links \(name) (remoteInfo=\(remoteInfo), remoteGlobalID=\(remoteUUID)) via PBXReferenceProxy in the Frameworks phase but has no matching PBXTargetDependency edge — the build graph still imports the remote target, so under explicit modules this can produce duplicate target-ID nodes; add a target dependency via add_dependency to give the link an explicit ordering edge.",
                ))
            }
        }
    }

    // MARK: - Stale remoteInfo

    /// Flags PBXContainerItemProxy objects that point at the same `remoteGlobalID` but disagree on
    /// `remoteInfo`. `remoteInfo` is the cached name of the target at proxy-creation time, so
    /// divergent values indicate a target was renamed without refreshing its consumer proxies.
    /// In the explicit-modules build system this can cause Xcode to import the same target as
    /// distinct graph nodes that collide on `target-<Name>-<hash>-SDKROOT:<sdk>` IDs.
    private func checkStaleRemoteInfo(
        xcodeproj: XcodeProj,
        diagnostics: inout [Diagnostic],
    ) {
        var groups: [String: [PBXContainerItemProxy]] = [:]
        var resolvedName: [String: String] = [:]

        for proxy in xcodeproj.pbxproj.containerItemProxies {
            guard let remote = proxy.remoteGlobalID else { continue }
            let key: String
            switch remote {
                case let .object(obj):
                    key = obj.uuid
                    if resolvedName[key] == nil {
                        resolvedName[key] = (obj as? PBXTarget)?.name
                    }
                case let .string(uuid):
                    key = uuid
            }
            groups[key, default: []].append(proxy)
        }

        for (key, proxies) in groups where proxies.count > 1 {
            let infos = Set(proxies.compactMap(\.remoteInfo))
            guard infos.count > 1 else { continue }
            let name = resolvedName[key] ?? "<unresolved>"
            let infoList = infos.sorted().map { "'\($0)'" }.joined(separator: ", ")
            diagnostics.append(Diagnostic(
                .warning,
                "Stale remoteInfo across \(proxies.count) proxies referencing target \(name) (\(key)): \(infos.count) distinct values [\(infoList)] — a target was likely renamed without refreshing its consumer proxies; remove_dependency + add_dependency on each affected consumer will rebuild them with the current name.",
            ))
        }
    }
}

// MARK: - Diagnostic Model

extension ValidateProjectTool {
    enum Severity {
        case error, warning, info

        var label: String {
            switch self {
                case .error: "[error]"
                case .warning: "[warn] "
                case .info: "[info] "
            }
        }
    }

    struct Diagnostic {
        let severity: Severity
        let message: String

        init(_ severity: Severity, _ message: String) {
            self.severity = severity
            self.message = message
        }

        var formatted: String { "\(severity.label) \(message)" }
    }
}
