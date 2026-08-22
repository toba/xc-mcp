import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Removes a sub-project reference and every object that hangs off it.
///
/// A sub-project reaches a consumer target through four linked objects: a `PBXFileReference` for
/// the child project bundle, a `PBXContainerItemProxy` naming a remote object inside it, a
/// `PBXReferenceProxy` standing in for each product it vends, and a `PBXBuildFile` per build phase
/// that names one of those proxies. Deleting only the file reference strands the rest, and the
/// write-time reference audit refuses that write. This tool removes the whole cluster in one pass.
public struct RemoveSubprojectTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_subproject",
            description:
                "Remove a sub-project (cross-project) reference and everything it wires up: the child project's PBXFileReference, its Products group, every PBXReferenceProxy vended through it, every PBXContainerItemProxy that names it, every PBXBuildFile in a Link Binary or Copy Files phase that names one of those proxies, and every PBXTargetDependency edge through it. Use this after deleting a sub-project from disk, when remove_framework reports 'not found' (it matches file references, not proxies) and remove_file refuses with a dangling-reference error.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the consumer .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "subproject_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path of the referenced sub-project to remove. Accepts an absolute path, a path relative to the consumer project's directory, a trailing suffix such as 'GRDB/GRDBCustom.xcodeproj', or the bare bundle name 'GRDBCustom.xcodeproj'. The sub-project does not need to still exist on disk.",
                        ),
                    ]),
                    "dry_run": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Report what would be removed and write nothing. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("subproject_path")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(subprojectPath) = arguments["subproject_path"]
        else { throw MCPError.invalidParams("project_path and subproject_path are required") }

        let dryRun = arguments.getBool("dry_run")

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let sourceRoot = Path(projectURL.deletingLastPathComponent().path)
            let projectFilePath = Path(projectURL.path)

            let preimage = PBXProjWriter.preimage(of: projectFilePath)
            let xcodeproj = try XcodeProj(path: projectFilePath)
            let pbxproj = xcodeproj.pbxproj

            guard let rootObject = pbxproj.rootObject else {
                throw MCPError.internalError("Project has no root object")
            }

            let matches = Self.matchingEntries(
                in: rootObject, sourceRoot: sourceRoot, subprojectPath: subprojectPath,
            )

            if matches.isEmpty {
                return .text(Self.notFoundMessage(in: rootObject, subprojectPath: subprojectPath))
            }

            if matches.count > 1 {
                let list = matches
                    .map { "  - \($0.projectRef.path ?? $0.projectRef.name ?? $0.projectRef.uuid)" }
                    .joined(separator: "\n")
                return .text(
                    "'\(subprojectPath)' matches \(matches.count) sub-project references. Pass a longer path to disambiguate:\n\(list)",
                )
            }

            let entry = matches[0]
            let removal = Self.plan(for: entry, in: pbxproj)
            let label = entry.projectRef.path ?? entry.projectRef.name ?? entry.projectRef.uuid

            if dryRun {
                return .text("Dry run — would remove sub-project '\(label)':\n\(removal.summary)")
            }

            Self.apply(removal, entry: entry, rootObject: rootObject, pbxproj: pbxproj)

            try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)

            return .text("Removed sub-project '\(label)':\n\(removal.summary)")
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove sub-project: \(error.localizedDescription)",
            )
        }
    }

    // MARK: - Matching

    private struct Entry {
        let index: Int
        let projectRef: PBXFileReference
        let productGroup: PBXGroup?
    }

    private static func matchingEntries(
        in rootObject: PBXProject,
        sourceRoot: Path,
        subprojectPath: String,
    ) -> [Entry] {
        let normalized = subprojectPath.hasPrefix("/")
            ? URL(fileURLWithPath: subprojectPath).standardizedFileURL.path
            : (sourceRoot + Path(subprojectPath)).absolute().string

        var matched: [Entry] = []

        for (index, dict) in rootObject.projects.enumerated() {
            guard let projectRef = dict["ProjectRef"] as? PBXFileReference else { continue }

            let refPath = projectRef.path ?? projectRef.name ?? ""
            let absolutePath = (try? projectRef.fullPath(sourceRoot: sourceRoot))?
                .absolute().string

            let matches = absolutePath == normalized
                || refPath == subprojectPath
                || refPath.hasSuffix("/" + subprojectPath)
                || (refPath as NSString).lastPathComponent == subprojectPath
                || (absolutePath?.hasSuffix("/" + subprojectPath) ?? false)

            if matches {
                matched.append(Entry(
                    index: index, projectRef: projectRef,
                    productGroup: dict["ProductGroup"] as? PBXGroup,
                ))
            }
        }
        return matched
    }

    private static func notFoundMessage(
        in rootObject: PBXProject,
        subprojectPath: String
    ) -> String {
        let known = rootObject.projects.compactMap { dict -> String? in
            guard let ref = dict["ProjectRef"] as? PBXFileReference else { return nil }
            return "  - " + (ref.path ?? ref.name ?? ref.uuid)
        }
        return known.isEmpty
            ? "Project references no sub-projects, so '\(subprojectPath)' cannot be removed"
            : "Sub-project '\(subprojectPath)' is not referenced by this project. Referenced sub-projects:\n\(known.joined(separator: "\n"))"
    }

    // MARK: - Planning

    /// The object cluster a single sub-project reference owns, gathered before anything is deleted
    /// so a dry run and a real removal report the same counts.
    private struct Removal {
        var referenceProxies: [PBXReferenceProxy] = []
        var containerProxies: [PBXContainerItemProxy] = []
        var buildFiles: [PBXBuildFile] = []
        var targetDependencies: [(target: PBXTarget, dependency: PBXTargetDependency)] = []
        /// Names of the products whose proxies get removed, for the report.
        var productNames: [String] = []
        /// Names of the targets that lose a build-phase entry or a dependency edge.
        var affectedTargets: Set<String> = []

        var summary: String {
            var lines: [String] = []
            if !productNames.isEmpty {
                let noun = referenceProxies.count == 1 ? "proxy" : "proxies"
                lines.append(
                    "  - \(referenceProxies.count) reference \(noun): \(productNames.joined(separator: ", "))",
                )
            }
            let proxyNoun = containerProxies.count == 1 ? "proxy" : "proxies"
            lines.append("  - \(containerProxies.count) container item \(proxyNoun)")
            let fileNoun = buildFiles.count == 1 ? "entry" : "entries"
            lines.append("  - \(buildFiles.count) build file \(fileNoun)")
            let edgeNoun = targetDependencies.count == 1 ? "edge" : "edges"
            lines.append("  - \(targetDependencies.count) target dependency \(edgeNoun)")
            if !affectedTargets.isEmpty {
                let names = affectedTargets.sorted().joined(separator: ", ")
                lines.append("  - affected targets: \(names)")
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func plan(for entry: Entry, in pbxproj: PBXProj) -> Removal {
        var removal = Removal()

        // Every container item proxy whose portal is the child project bundle. This covers both the
        // reference proxies (proxyType 2) and the target dependency edges (proxyType 1).
        removal.containerProxies = pbxproj.containerItemProxies.filter { proxy in
            guard case let .fileReference(ref) = proxy.containerPortal else { return false }
            return ref === entry.projectRef
        }
        let containerUUIDs = Set(removal.containerProxies.map(\.uuid))

        // Reference proxies reached two ways: through a container proxy above, or by sitting in the
        // sub-project's Products group. A malformed project can have one without the other.
        var proxiesByUUID: [String: PBXReferenceProxy] = [:]
        for proxy in pbxproj.referenceProxies
            where containerUUIDs.contains(proxy.remote?.uuid ?? "")
        { proxiesByUUID[proxy.uuid] = proxy }
        for child in entry.productGroup?.children ?? [] {
            if let proxy = child as? PBXReferenceProxy { proxiesByUUID[proxy.uuid] = proxy }
        }
        removal.referenceProxies = Array(proxiesByUUID.values)
        removal.productNames = removal.referenceProxies
            .map { $0.path ?? $0.name ?? $0.uuid }
            .sorted()

        // Build files naming one of those proxies, plus the target that owns the phase.
        for target in pbxproj.projects.flatMap(\.targets) {
            for phase in target.buildPhases {
                for buildFile in phase.files ?? [] {
                    guard let file = buildFile.file as? PBXReferenceProxy,
                          proxiesByUUID[file.uuid] != nil else { continue }
                    removal.buildFiles.append(buildFile)
                    removal.affectedTargets.insert(target.name)
                }
            }
        }

        // Target dependency edges routed through one of the container proxies.
        for target in pbxproj.projects.flatMap(\.targets) {
            for dependency in target.dependencies
                where containerUUIDs.contains(dependency.targetProxy?.uuid ?? "")
            {
                removal.targetDependencies.append((target, dependency))
                removal.affectedTargets.insert(target.name)
            }
        }

        return removal
    }

    // MARK: - Applying

    private static func apply(
        _ removal: Removal,
        entry: Entry,
        rootObject: PBXProject,
        pbxproj: PBXProj,
    ) {
        // Snapshot the surviving entries first. The `projects` getter force-unwraps every element's
        // object, so it must not be read after the doomed ProjectRef is deleted.
        var remaining = rootObject.projects
        remaining.remove(at: entry.index)

        let doomedBuildFiles = Set(removal.buildFiles.map(\.uuid))
        for target in pbxproj.projects.flatMap(\.targets) {
            for phase in target.buildPhases {
                phase.files?.removeAll { doomedBuildFiles.contains($0.uuid) }
            }
        }
        for buildFile in removal.buildFiles { pbxproj.delete(object: buildFile) }

        for (target, dependency) in removal.targetDependencies {
            target.dependencies.removeAll { $0 === dependency }
            pbxproj.delete(object: dependency)
        }

        // Detach each proxy from the Products group before deleting it, so the group's children
        // list never names a deleted object.
        for proxy in removal.referenceProxies {
            entry.productGroup?.children.removeAll { $0 === proxy }
            detach(proxy, from: rootObject.mainGroup)
            pbxproj.delete(object: proxy)
        }

        for proxy in removal.containerProxies { pbxproj.delete(object: proxy) }

        if let productGroup = entry.productGroup {
            detach(productGroup, from: rootObject.mainGroup)
            pbxproj.delete(object: productGroup)
        }

        detach(entry.projectRef, from: rootObject.mainGroup)
        pbxproj.delete(object: entry.projectRef)

        rootObject.projects = remaining
    }

    /// Recursively removes `element` from `group`'s children and from every nested group.
    private static func detach(_ element: PBXFileElement, from group: PBXGroup?) {
        guard let group else { return }
        group.children.removeAll { $0 === element }
        for child in group.children {
            if let subgroup = child as? PBXGroup { detach(element, from: subgroup) }
        }
    }
}

private extension CallTool.Result {
    static func text(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }
}
