import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Resolves an Xcode project's Swift Package dependencies, and optionally forces one package or
/// every package to the newest version its requirement allows.
///
/// A plain resolve reuses the pins in `Package.resolved`, so a newly tagged release is ignored even
/// when the project's requirement allows it. `update: true` drops the pin first, which is what
/// makes resolution choose the newer tag. Naming a package keeps the blast radius to that one
/// dependency, so nine unrelated packages do not jump versions at the same time.
///
/// Resolution reuses a checkout that already satisfies the requirement, and then writes no pin for
/// it. A drop that resolution does not replace therefore leaves the package out of
/// `Package.resolved` altogether, so the call fails and the prior pins go back. The failure text
/// names the requirement that admits the pin and the file declaring it, because a package reached
/// through a local package states its requirement in that package's `Package.swift`.
///
/// Three caches sit between a published tag and a written pin, and an update clears them itself
/// rather than asking the caller which one is stale. It fetches the mirrors and drops the working
/// copies before resolving, which is the cheap half. A pin still left unwritten sends the whole
/// `SourcePackages` tree away and resolves once more, which is the reliable half.
/// ``SourcePackagesCache`` holds what each copy does.
public struct ResolvePackagesTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let gitRunner: GitRunner
    private let pathUtility: PathUtility
    private let resolvedParser: PackageResolvedParser
    private let resolvedEditor: PackageResolvedEditor

    public init(
        pathUtility: PathUtility,
        xcodebuildRunner: XcodebuildRunner = .init(),
        gitRunner: GitRunner = .init(),
        resolvedParser: PackageResolvedParser = .init(),
        resolvedEditor: PackageResolvedEditor = .init(),
    ) {
        self.pathUtility = pathUtility
        self.xcodebuildRunner = xcodebuildRunner
        self.gitRunner = gitRunner
        self.resolvedParser = resolvedParser
        self.resolvedEditor = resolvedEditor
    }

    public func tool() -> Tool {
        .init(
            name: "resolve_packages",
            description:
                "Resolve an Xcode project's Swift Package dependencies. With update: true, drops "
                + "the pin for one named package (or for every package) first, so resolution picks "
                + "the newest version each requirement allows. This is the command-line form of "
                + "Xcode's 'Update to Latest Package Versions'. An update refreshes the package "
                + "mirrors first, and clears the whole SourcePackages tree and resolves again when a "
                + "pin is still left unwritten, so no cache has to be cleared by hand. A dropped pin "
                + "that resolution does not write back fails the call, and Package.resolved goes "
                + "back as it was.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Use instead of project_path.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Scheme to resolve for. Optional; omit to resolve the whole project.",
                        ),
                    ]),
                    "update": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, drop the existing pin before resolving so the newest "
                                + "allowed version wins. Defaults to false.",
                        ),
                    ]),
                    "package_url": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Limit an update to this one package URL. Omit with update: true to "
                                + "update every package, which can move many dependencies at once.",
                        ),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "description": .string(
                            "xcodebuild destination whose DerivedData tree receives the resolved "
                                + "checkouts, for example 'platform=iOS Simulator,name=iPhone 16'. "
                                + "Defaults to 'platform=macOS'. Pass the destination you build "
                                + "with, otherwise that build re-clones every checkout into its own "
                                + "platform-scoped tree.",
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum time in seconds for resolution. Defaults to 300.",
                        ),
                    ]),
                ].merging([String: Value].outputTimeoutSchemaProperty(
                    defaultSeconds: 120,
                    note: "A first resolution that clones a large repository stays silent for "
                        + "minutes, so raise the overall timeout rather than this one.",
                ),
                ) { _, new in new }),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(
        arguments: [String: Value],
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> CallTool.Result {
        var projectPath: String?
        var workspacePath: String?

        if let raw = arguments.getString("project_path") {
            projectPath = try pathUtility.resolvePath(from: raw)
        }

        if let raw = arguments.getString("workspace_path") {
            workspacePath = try pathUtility.resolvePath(from: raw)
        }

        guard let container = workspacePath ?? projectPath else {
            throw MCPError.invalidParams("Either project_path or workspace_path is required")
        }

        let update = arguments.getBool("update")
        let packageURL = arguments.getString("package_url")
        let scheme = arguments.getString("scheme")
        let destination = arguments.getString("destination")
            ?? XcodebuildRunner.macOSDestination
        let timeout = arguments.resolveTimeout(default: XcodebuildRunner.defaultTimeout)

        if packageURL != nil, !update {
            throw MCPError.invalidParams(
                "package_url only applies with update: true. A plain resolve reuses every pin.",
            )
        }

        var lines: [String] = []

        let before = resolvedParser.pinsByIdentity(for: container)

        // Package.resolved is a checked-in file. Dropping a pin and then failing to resolve would
        // leave the project silently unpinned, so keep the original bytes and put them back on
        // every failure path.
        let backup = update ? PinsFileBackup(container: container, parser: resolvedParser) : nil
        let cache = update
            ? SourcePackagesCache.locate(
                workspacePath: workspacePath, projectPath: projectPath, destination: destination,
            )
            : nil
        // A plain resolve reads no cache, so it needs no target list either.
        let targets = update
            ? packageURL.map { [PackageResolvedParser.identity(forURL: $0)] }
                ?? before.keys.sorted()
            : []
        // One target names the package the cache advice belongs to. Every other count leaves the
        // advice unable to name one.
        let updated = targets.count == 1 ? targets[0] : nil

        // Nothing re-fetches a mirror once it exists, so a tag published afterwards is invisible
        // and resolution re-clones the same version. The refresh therefore runs before the drop
        // rather than as advice after a failure. It runs whether or not the tree exists yet, since
        // the shared cache a first clone reads can be just as old.
        if let cache {
            await lines.append(contentsOf: cache.refresh(identities: targets, git: gitRunner))
        }

        if update {
            do {
                try lines.append(contentsOf: dropPins(for: container, packageURL: packageURL))
            } catch {
                backup?.restore()
                throw error
            }
        }

        let run = ResolveRun(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            destination: destination,
            timeout: timeout,
            outputTimeout: arguments.resolveOutputTimeout(
                default: XcodebuildRunner.deviceOutputTimeout,
            ),
        )
        try await resolve(
            run, backup: backup, cache: cache, identity: updated, onProgress: onProgress)

        var after = resolvedParser.pinsByIdentity(for: container)
        var unreplaced = Self.unreplacedPins(before: before, after: after)
        var clearedTree = false

        // A refreshed mirror still leaves a pin unwritten when a third copy of the package is
        // stale, and only the whole tree going answers that. One more resolve costs less than
        // asking the caller to guess which of three caches holds the old version.
        if let backup, !unreplaced.isEmpty, let cache, cache.exists {
            lines.append(
                "Resolution left \(unreplaced.count) package(s) unpinned, so the whole tree at "
                    + "\(cache.directory) went and the resolve ran again.",
            )
            backup.restore()
            clearedTree = cache.clear()

            do {
                try lines.append(contentsOf: dropPins(for: container, packageURL: packageURL))
            } catch {
                backup.restore()
                throw error
            }
            try await resolve(
                run, backup: backup, cache: cache, identity: updated, onProgress: onProgress)
            after = resolvedParser.pinsByIdentity(for: container)
            unreplaced = Self.unreplacedPins(before: before, after: after)
        }

        if let backup, !unreplaced.isEmpty {
            let diagnosed = unreplaced.map { identity in
                UnreplacedPin(
                    identity: identity,
                    pinnedState: before[identity]?.stateDescription ?? "(unknown)",
                    requirement: PackageRequirementLocator.requirement(
                        for: identity, pinned: before[identity]?.version, in: container,
                    ),
                )
            }
            throw MCPError.internalError(Self.unreplacedPinsMessage(
                diagnosed, restored: backup.restore(),
                cacheNotes: Self.cacheNotes(
                    cache: cache, identities: unreplaced, cleared: clearedTree,
                ),
            ))
        }

        lines.append("Package resolution succeeded.")
        lines.append(contentsOf: PinMove.lines(
            PinMove.moves(from: before, to: after), header: "Pin changes:",
            whenEmpty: "No pin changed.",
        ))
        lines.append(DerivedDataScoper.note(
            workspacePath: workspacePath, projectPath: projectPath, destination: destination,
        ))

        return CallTool.Result.text(lines.joined(separator: "\n"))
    }

    // MARK: - Resolving

    /// The inputs of one resolve, so the retry repeats it without repeating its arguments
    private struct ResolveRun: Sendable {
        let projectPath: String?
        let workspacePath: String?
        let scheme: String?
        let destination: String
        let timeout: TimeInterval
        let outputTimeout: Duration?
    }

    /// Runs one resolve and turns a failure into the tool's error.
    ///
    /// - Parameters:
    ///   - run: What to resolve, and the budgets it runs under.
    ///   - backup: The pins snapshot to put back when the resolve fails.
    ///   - cache: The package caches, for the advice a failed checkout earns.
    ///   - identity: The one package under update, absent when the update covers every one.
    ///   - onProgress: The MCP progress callback.
    /// - Throws: ``MCPError/internalError(_:)`` carrying the failure text and what it restored.
    private func resolve(
        _ run: ResolveRun,
        backup: PinsFileBackup?,
        cache: SourcePackagesCache?,
        identity: String?,
        onProgress: (@Sendable (String) -> Void)?,
    ) async throws {
        let result: ProcessResult

        do {
            result = try await xcodebuildRunner.resolvePackageDependencies(
                projectPath: run.projectPath,
                workspacePath: run.workspacePath,
                scheme: run.scheme,
                destination: run.destination,
                timeout: run.timeout,
                outputTimeout: run.outputTimeout,
                onProgress: onProgress,
            )
        } catch {
            backup?.restore()
            throw try error.asMCPError()
        }

        guard result.succeeded else {
            var message = "Package resolution failed:\n" + result.errorOutput

            if let advice = MacroApprovalAdvice.advice(for: result.output) {
                message += "\n\n" + advice
            }

            if let advice = cache?.revisionAdvice(for: result.output, identity: identity) {
                message += "\n\n" + advice
            }

            if let backup {
                message += backup.restore()
                    ? "\n\nPackage.resolved was restored to its prior state."
                    : "\n\nWARNING: Package.resolved could not be restored. Its pins may be "
                        + "incomplete. Check the file into review before building."
            }
            throw MCPError.internalError(message)
        }
    }

    // MARK: - Pins

    /// Drops the pin for one package, or every pin, and reports what it dropped.
    private func dropPins(for container: String, packageURL: String?) throws -> [String] {
        guard let file = resolvedParser.locate(for: container) else {
            return ["No Package.resolved found — resolution starts from scratch."]
        }

        let identities = packageURL.map { Set([PackageResolvedParser.identity(forURL: $0)]) }

        do {
            let removed = try resolvedEditor.removePins(fileAt: file, identities: identities)

            if removed.isEmpty {
                guard let packageURL else { return ["Package.resolved held no pins to drop."] }
                throw MCPError.invalidParams(
                    "No pin for '\(packageURL)' in \(file). Check the URL, or omit package_url to "
                        + "update every package.",
                )
            }
            return ["Dropped \(removed.count) pin(s): " + removed.joined(separator: ", ")]
        } catch let error as PackageResolvedEditor.EditError {
            throw MCPError.internalError(
                error.errorDescription ?? "Could not rewrite Package.resolved",
            )
        }
    }

    /// The pins that resolution did not write back after the update dropped them.
    ///
    /// Resolution reuses a checkout that already satisfies the requirement, and writes no pin for
    /// it. The entry the drop removed then stays missing, so a package still in the graph loses its
    /// pin while the call reports success.
    ///
    /// - Parameters:
    ///   - before: The pins read before the drop, keyed by identity.
    ///   - after: The pins read after resolution, keyed by identity.
    /// - Returns: The identities present before and missing after, sorted.
    static func unreplacedPins(
        before: [String: ResolvedPin],
        after: [String: ResolvedPin],
    ) -> [String] { before.keys.filter { after[$0] == nil }.sorted() }

    /// One package resolution left out of the pins file, with the requirement that explains it
    struct UnreplacedPin: Sendable, Equatable {
        let identity: String

        /// The state the dropped pin held, such as `1.2.1`
        let pinnedState: String

        /// The requirement a file in reach declares, absent when the search found none
        let requirement: DeclaredRequirement?
    }

    /// The failure text for pins resolution left out of the file.
    ///
    /// Two different situations produce the same missing entry, and they take opposite remedies. A
    /// requirement that still admits the pinned version leaves resolution nothing newer to write,
    /// and only an edit to the file declaring that requirement moves the pin. A requirement the
    /// pinned version no longer satisfies points at a stale checkout instead. The per-package lines
    /// say which one applies rather than stating one cause for both.
    ///
    /// - Parameters:
    ///   - pins: The packages that lost their pin, each with the requirement found for it.
    ///   - restored: Whether the prior pins file went back in place.
    ///   - cacheNotes: The lines naming the caches, from ``cacheNotes(cache:identities:cleared:)``.
    static func unreplacedPinsMessage(
        _ pins: [UnreplacedPin],
        restored: Bool,
        cacheNotes: [String] = [],
    ) -> String {
        var lines = [
            "Package resolution succeeded but left \(pins.count) package(s) unpinned: "
                + pins.map(\.identity).joined(separator: ", ")
                + ". Resolution reused a checkout that already satisfied the requirement, so it "
                + "wrote no pin back and Package.resolved lost the entry."
                + (restored
                    ? " Package.resolved was restored to its prior state, so no version moved."
                    : " WARNING: Package.resolved could not be restored and is missing those pins. "
                        + "Recover it from version control before building.")
        ]

        for pin in pins {
            lines.append("")
            lines.append(contentsOf: detail(of: pin))
        }

        if !cacheNotes.isEmpty {
            lines.append("")
            lines.append(contentsOf: cacheNotes)
        }
        return lines.joined(separator: "\n")
    }

    /// The lines that name every cache able to hold a copy older than the published tag.
    ///
    /// The message needs all three paths, because deleting the working copy alone re-clones the
    /// same version out of a mirror nothing re-fetches, and a fresh mirror comes from a shared
    /// cache that can be just as old.
    ///
    /// - Parameters:
    ///   - cache: The tree the resolve used, absent when no tree could be named.
    ///   - identities: The packages that lost their pin.
    ///   - cleared: Whether the tool already cleared the tree and resolved again.
    static func cacheNotes(
        cache: SourcePackagesCache?,
        identities: [String],
        cleared: Bool,
    ) -> [String] {
        guard let cache else { return [] }
        let opening = cleared
            ? "The whole tree at \(cache.directory) was cleared and the resolve ran again, so a "
                + "stale copy is not the reason. These are the caches it holds:"
            : "These caches can each hold a copy older than the published tag, and the whole tree at "
                + "\(cache.directory) may need to go:"
        return [opening] + identities.flatMap { cache.pathNotes(for: $0) }
    }

    /// The lines for one unpinned package: what admits the pin, and where the requirement sits.
    private static func detail(of pin: UnreplacedPin) -> [String] {
        let opening = "\(pin.identity): pinned \(pin.pinnedState)"

        guard let requirement = pin.requirement else {
            return [
                opening + ", and no project or manifest in reach declares it. A cached copy older "
                    + "than the published tag is the likely reason, so clear the paths named below."
            ]
        }

        switch requirement.admission {
            case .admits:
                return [
                    opening
                        + ", and the requirement '\(requirement.requirement)' still admits that "
                        + "version, so resolution had nothing newer to write. The checkout is not "
                        + "the reason.",
                    remedy(for: requirement),
                ]
            case .unknown:
                return [
                    opening
                        + ", and the requirement '\(requirement.requirement)' states no version "
                        + "window to compare the pin against.",
                    remedy(for: requirement),
                ]
            case .excludes:
                return [
                    opening + ", and the requirement '\(requirement.requirement)' in "
                        + "\(requirement.file) excludes that version, so a cached copy is the "
                        + "reason. Clear the paths named below."
                ]
        }
    }

    /// The file a requirement sits in, and the edit that moves the pin it holds back.
    private static func remedy(for requirement: DeclaredRequirement) -> String {
        switch requirement.source {
            case .project:
                "The project declares it in \(requirement.file). Move the requirement with "
                    + "update_swift_package, then run this call again."
            case .manifest:
                "A local package's manifest declares it, in \(requirement.file). "
                    + "update_swift_package and show_package_resolution read the project's own "
                    + "packages alone, so change the requirement in that file, then run this call "
                    + "again."
        }
    }
}
