import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Raises version pins across a set of repositories, one dependency layer at a time
///
/// The sweep runs in three phases. It loads and checks every member, it plans every edit without
/// writing, and only then does it write, commit, tag and push. A member publishes before the
/// members that pin it are edited, because a dependent can only pin a version the remote already
/// carries.
///
/// A member's identity is its directory name. That is what a repository URL's last path component
/// resolves to, so a member cloned under a different directory name takes no edges in the graph.
public struct PinSyncEngine: Sendable {
    private let git: GitRunner
    private let swift: SwiftRunner

    public init(git: GitRunner = .init(), swift: SwiftRunner = .init()) {
        self.git = git
        self.swift = swift
    }

    /// Runs the sweep and returns the report.
    ///
    /// - Parameter request: What to update, where, and whether to write.
    /// - Returns: The report text.
    /// - Throws: ``MCPError/invalidParams(_:)`` when a member cannot be loaded, when the members
    ///   form a dependency cycle, or when any member blocks the run.
    public func run(_ request: PinSyncRequest) async throws(MCPError) -> String {
        let members = try load(request.members)
        var blockers = await preflight(members)
        await blockers.append(contentsOf: verifyUpdates(request, members: members))
        guard blockers.isEmpty else { throw MCPError.invalidParams(refusal(blockers)) }

        let order = try order(members)
        var planned = try await planEdits(request, members: members, order: order)

        guard !request.dryRun else { return dryRunReport(planned, order: order) }
        let failure = await apply(&planned, order: order, request: request)
        return applyReport(planned, order: order, failure: failure)
    }

    // MARK: - Load and check

    /// Loads every member and refuses a list that names one package twice.
    private func load(_ paths: [String]) throws(MCPError) -> [String: PinSyncMember] {
        var members: [String: PinSyncMember] = [:]
        members.reserveCapacity(paths.count)

        for path in paths {
            let member = try PinSyncMember.load(root: path)

            if let existing = members[member.identity] {
                throw .invalidParams(
                    "Two members resolve to the identity '\(member.identity)': "
                        + "\(existing.root) and \(member.root)",
                )
            }
            members[member.identity] = member
        }
        return members
    }

    /// Checks every member before any member is written.
    private func preflight(_ members: [String: PinSyncMember]) async -> [PinSyncBlocker] {
        var blockers: [PinSyncBlocker] = []

        for identity in members.keys.sorted() {
            guard let member = members[identity] else { continue }
            await blockers.append(contentsOf: PinSyncPreflight.check(member, git: git))
        }
        return blockers
    }

    /// Refuses an update naming a version that no repository publishes yet.
    ///
    /// Raising a floor to a version nobody tagged makes every resolve below it fail, one layer at a
    /// time, after the first layer has already pushed. Checking the tag up front keeps that failure
    /// out of the write phase.
    private func verifyUpdates(
        _ request: PinSyncRequest,
        members: [String: PinSyncMember],
    ) async -> [PinSyncBlocker] {
        var blockers: [PinSyncBlocker] = []

        for update in request.updates {
            if let member = members[update.identity] {
                let tags = (try? await git.localVersionTags(repository: member.root)) ?? []

                if !tags.contains(update.version) {
                    blockers.append(.init(
                        member: update.identity,
                        reason: "holds no tag \(update.version). Tag the release and fetch it "
                            + "before the sweep pins it",
                    ))
                }
                continue
            }

            guard let url = url(of: update.identity, in: members) else {
                blockers.append(.init(
                    member: update.identity,
                    reason: "is not a member and no member pins it, so the sweep cannot find it",
                ))
                continue
            }
            let tags = (try? await git.remoteVersionTags(repositoryURL: url)) ?? []

            if !tags.contains(update.version) {
                blockers.append(.init(
                    member: update.identity, reason: "publishes no tag \(update.version) at \(url)",
                ))
            }
        }
        return blockers
    }

    /// The repository URL a member declares for an identity it pins.
    private func url(of identity: String, in members: [String: PinSyncMember]) -> String? {
        for name in members.keys.sorted() {
            guard let member = members[name] else { continue }

            for manifest in member.manifests {
                if let pin = manifest.pins.first(where: { $0.identity == identity }) {
                    return pin.url
                }
            }
            if let pin = member.projectPins.first(where: { $0.identity == identity }) {
                return pin.url
            }
        }
        return nil
    }

    /// Sorts the members so each one follows the members it pins.
    private func order(_ members: [String: PinSyncMember]) throws(MCPError) -> [String] {
        do {
            return try PinGraph.topologicalOrder(members.mapValues(\.pinnedIdentities))
        } catch {
            throw .invalidParams(
                "The members form a dependency cycle, which has no publish order: "
                    + error.identities.joined(separator: ", "),
            )
        }
    }

    // MARK: - Plan

    /// Every edit one member takes, computed without writing anything
    struct PlannedMember {
        let member: PinSyncMember

        /// One entry per manifest whose text changed
        var manifestEdits: [ManifestEdit] = []

        /// One entry per project reference whose floor moved
        var projectEdits: [ManifestPinChange] = []

        /// Notes that do not block the run, such as a pin the sweep cannot raise
        var warnings: [String] = []

        /// The newest release tag the repository already holds
        var previousVersion: SemanticVersion?

        /// The version the sweep tags, absent when the member takes no tag
        var newVersion: SemanticVersion?

        /// Whether the member published, which the partial-failure report reads
        var published = false

        var changed: Bool { !manifestEdits.isEmpty || !projectEdits.isEmpty }
    }

    /// One manifest rewrite waiting to be written
    struct ManifestEdit {
        let manifest: PinSyncMember.Manifest
        let text: String
        let changes: [ManifestPinChange]
    }

    /// Computes every edit and every new version, and refuses a member that cannot be versioned.
    private func planEdits(
        _ request: PinSyncRequest,
        members: [String: PinSyncMember],
        order: [String],
    ) async throws(MCPError) -> [String: PlannedMember] {
        var versions: [String: SemanticVersion] = [:]
        for update in request.updates { versions[update.identity] = update.version }
        var planned: [String: PlannedMember] = [:]
        var blockers: [PinSyncBlocker] = []

        for identity in order {
            guard let member = members[identity] else { continue }
            var entry = PlannedMember(member: member)

            for manifest in member.manifests {
                let rewrite = ManifestPins.rewrite(manifest.text, pins: manifest.pins, to: versions)

                if !rewrite.changes.isEmpty {
                    entry.manifestEdits.append(.init(
                        manifest: manifest, text: rewrite.text, changes: rewrite.changes,
                    ))
                }
                entry.warnings.append(
                    contentsOf: unraisablePins(manifest.pins, versions: versions)
                        .map { "\(manifest.relativePath) pins \($0)" },
                )
            }
            entry.projectEdits = projectChanges(member.projectPins, versions: versions)
            entry.warnings.append(contentsOf: unraisableProjectPins(
                member.projectPins, versions: versions))

            if entry.changed, member.kind == .package, !request.noTag.contains(member.name) {
                switch await nextVersion(for: member, bump: request.bump) {
                    case let .success(step):
                        entry.previousVersion = step.previous
                        entry.newVersion = step.next
                        versions[identity] = step.next
                    case let .failure(reason):
                        blockers.append(.init(member: member.name, reason: reason))
                }
            }
            planned[identity] = entry
        }
        guard blockers.isEmpty else { throw MCPError.invalidParams(refusal(blockers)) }
        return planned
    }

    /// The version step a member takes, or the reason it can take none
    private enum VersionStep {
        case success(step: (previous: SemanticVersion, next: SemanticVersion))
        case failure(reason: String)
    }

    /// Reads a member's newest release tag and computes the version that follows it.
    private func nextVersion(for member: PinSyncMember, bump: VersionBump) async -> VersionStep {
        let tags = (try? await git.localVersionTags(repository: member.root)) ?? []

        guard let newest = tags.first(where: { !$0.isPrerelease }) else {
            return .failure(
                reason: "holds no release tag, so the sweep cannot compute the version its "
                    + "dependents would pin",
            )
        }
        let next = bump.next(after: newest)

        guard !tags.contains(next) else {
            return .failure(
                reason: "already holds the tag \(next) that a \(bump.rawValue) bump from "
                    + "\(newest) would create",
            )
        }
        return .success(step: (newest, next))
    }

    /// Names the pins that hold an updated package in a form the rewriter cannot move.
    private func unraisablePins(
        _ pins: [ManifestPin],
        versions: [String: SemanticVersion],
    ) -> [String] {
        pins.compactMap { pin in
            guard versions[pin.identity] != nil, case let .other(keyword) = pin.requirement
            else { return nil }
            return "\(pin.identity) as '\(keyword)', which the sweep leaves alone"
        }
    }

    /// Computes the project reference floors that move.
    private func projectChanges(
        _ pins: [PinSyncMember.ProjectPin],
        versions: [String: SemanticVersion],
    ) -> [ManifestPinChange] {
        pins.compactMap { ManifestPinChange.raising($0.identity, from: $0.version, to: versions) }
    }

    /// Names the project references that hold an updated package with no floor to move.
    private func unraisableProjectPins(
        _ pins: [PinSyncMember.ProjectPin],
        versions: [String: SemanticVersion],
    ) -> [String] {
        pins.compactMap { pin in
            guard versions[pin.identity] != nil, pin.version == nil else { return nil }
            return "the project pins \(pin.identity) as '\(pin.requirement)', which states no "
                + "version to raise"
        }
    }

    // MARK: - Apply

    /// Writes, commits, tags and pushes each changed member in order.
    ///
    /// - Returns: The first failure, or `nil` when every changed member published. A failure stops
    ///   the sweep, because the members above the failed one would pin a tag nobody pushed.
    private func apply(
        _ planned: inout [String: PlannedMember],
        order: [String],
        request: PinSyncRequest,
    ) async -> String? {
        for identity in order {
            guard var entry = planned[identity], entry.changed else { continue }

            do {
                try await publish(entry, request: request)
                entry.published = true
                planned[identity] = entry
            } catch {
                return "\(entry.member.name): \(error.localizedDescription)"
            }
        }
        return nil
    }

    /// Writes one member's edits, then commits, tags and pushes them.
    private func publish(_ entry: PlannedMember, request: PinSyncRequest) async throws {
        var stagePaths: [String] = []

        for edit in entry.manifestEdits {
            try edit.text.write(toFile: edit.manifest.path, atomically: true, encoding: .utf8)
            stagePaths.append(edit.manifest.relativePath)

            let directory = (edit.manifest.path as NSString).deletingLastPathComponent
            try await check(swift.resolve(packagePath: directory), step: "swift package resolve")
            let resolvedPath = Self.resolvedPath(besides: edit.manifest.relativePath)

            if FileManager.default.fileExists(atPath: entry.member.root + "/" + resolvedPath) {
                stagePaths.append(resolvedPath)
            }
        }

        if !entry.projectEdits.isEmpty, case let .xcodeProject(path) = entry.member.kind {
            try writeProjectEdits(entry.projectEdits, at: path)
            stagePaths.append(URL(fileURLWithPath: path).lastPathComponent)
        }
        try await check(git.add(paths: stagePaths, repository: entry.member.root), step: "git add")
        try await check(
            git.commit(
                message: message(for: entry, override: request.messageOverride),
                repository: entry.member.root,
            ),
            step: "git commit",
        )

        if let version = entry.newVersion {
            try await check(
                git.tag(
                    version.description,
                    message: "\(entry.member.name) \(version)",
                    repository: entry.member.root,
                ),
                step: "git tag \(version)",
            )
        }
        try await check(git.push(repository: entry.member.root), step: "git push")

        if let version = entry.newVersion {
            try await check(
                git.pushTag(
                    version.description, remote: request.remote, repository: entry.member.root,
                ),
                step: "git push \(request.remote) \(version)",
            )
        }
    }

    /// The pins file that sits beside a manifest.
    static func resolvedPath(besides manifestPath: String) -> String {
        let directory = (manifestPath as NSString).deletingLastPathComponent
        return directory.isEmpty ? "Package.resolved" : directory + "/Package.resolved"
    }

    /// Rewrites the floors an Xcode project's remote package references state.
    private func writeProjectEdits(_ edits: [ManifestPinChange], at path: String) throws {
        let preimage = PBXProjWriter.preimage(of: Path(path))
        let xcodeproj = try XcodeProj(path: Path(path))

        guard let project = try xcodeproj.pbxproj.rootProject() else {
            throw PinSyncError.step("cannot read the root object of \(path)")
        }
        var wanted: [String: SemanticVersion] = [:]
        for edit in edits { wanted[edit.identity] = edit.to }

        for reference in project.remotePackages {
            let identity = PackageResolvedParser.identity(forURL: reference.repositoryURL ?? "")

            guard let version = wanted[identity],
                  let requirement = reference.versionRequirement,
                  let raised = PackageRequirement.raised(requirement, to: version) else { continue }
            reference.versionRequirement = raised
        }
        try PBXProjWriter.write(xcodeproj, to: Path(path), expectedPreimage: preimage)
    }

    /// Turns a non-zero exit into a failure the report can name.
    private func check(_ result: ProcessResult, step: String) throws {
        guard result.succeeded else { throw PinSyncError.step("\(step) failed:\n\(result.output)") }
    }

    /// The commit subject and body for one member's edits.
    private func message(for entry: PlannedMember, override: String?) -> String {
        let changes = entry.manifestEdits.flatMap(\.changes) + entry.projectEdits
        let subject = override
            ?? (changes.count == 1
                ? "Raise \(changes[0].identity) to \(changes[0].to)"
                : "Raise \(changes.count) dependency pins")
        let body = changes.map { "- \($0.identity) \($0.from) → \($0.to)" }
            .joined(separator: "\n")
        return "\(subject)\n\n\(body)"
    }

    // MARK: - Reports

    /// The refusal text, which names every blocked member and writes nothing.
    private func refusal(_ blockers: [PinSyncBlocker]) -> String {
        var lines = [
            "The sweep wrote nothing. \(blockers.count) blocker"
                + "\(blockers.count == 1 ? "" : "s") must clear first:",
            "",
        ]

        for blocker in blockers.sorted(by: { ($0.member, $0.reason) < ($1.member, $1.reason) }) {
            lines.append("- \(blocker.member) \(blocker.reason)")
        }
        lines.append("")
        lines.append("Clear each one, then run the sweep again.")
        return lines.joined(separator: "\n")
    }

    /// The plan, rendered without writing anything.
    private func dryRunReport(_ planned: [String: PlannedMember], order: [String]) -> String {
        var lines = ["Dry run. Nothing was written, committed, tagged or pushed.", ""]
        lines.append(contentsOf: body(planned, order: order))
        lines.append("")
        lines.append("Pass dry_run: false to carry the plan out.")
        return lines.joined(separator: "\n")
    }

    /// The outcome of a run that wrote.
    private func applyReport(
        _ planned: [String: PlannedMember],
        order: [String],
        failure: String?,
    ) -> String {
        let published = order.compactMap { planned[$0] }.filter(\.published)
        var lines: [String] = []

        if let failure {
            lines.append("The sweep stopped at \(failure)")
            lines.append("")
            lines.append(
                published.isEmpty
                    ? "Nothing published, so no repository moved."
                    : "These repositories published already, and a rerun skips them: "
                        + published.map(\.member.name).joined(separator: ", "),
            )
        } else {
            lines.append(
                "Published \(published.count) repositor\(published.count == 1 ? "y" : "ies").",
            )
        }
        lines.append("")
        lines.append(contentsOf: body(planned, order: order))
        return lines.joined(separator: "\n")
    }

    /// The per-member detail both reports share.
    private func body(_ planned: [String: PlannedMember], order: [String]) -> [String] {
        var lines = ["Order: " + order.joined(separator: " → "), ""]
        var unchanged: [String] = []

        for identity in order {
            guard let entry = planned[identity] else { continue }

            guard entry.changed else {
                unchanged.append(entry.member.name)
                continue
            }
            lines.append(entry.member.name + (entry.published ? " (published)" : ""))

            for edit in entry.manifestEdits {
                lines.append(
                    "  \(edit.manifest.relativePath): "
                        + edit.changes.map(\.description).joined(separator: ", "),
                )
            }

            if !entry.projectEdits.isEmpty {
                lines.append(
                    "  project: "
                        + entry.projectEdits.map(\.description).joined(separator: ", "),
                )
                lines.append(
                    "  note: the project's resolved pins still hold the old versions. Run "
                        + "resolve_packages to move them",
                )
            }

            if let version = entry.newVersion, let previous = entry.previousVersion {
                lines.append("  version \(previous) → \(version), tag \(version)")
            } else {
                lines.append("  no tag")
            }
            for warning in entry.warnings { lines.append("  note: \(warning)") }
        }

        if !unchanged.isEmpty {
            lines.append("")
            lines.append("Unchanged: " + unchanged.joined(separator: ", "))
        }
        return lines
    }
}

/// A step of the sweep that failed after the writes began
enum PinSyncError: Error, LocalizedError {
    case step(String)

    var errorDescription: String? {
        switch self {
            case let .step(detail): detail
        }
    }
}
