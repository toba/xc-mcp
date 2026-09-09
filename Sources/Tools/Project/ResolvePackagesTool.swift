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
/// `Package.resolved` altogether, so the call fails and the prior pins go back.
public struct ResolvePackagesTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let pathUtility: PathUtility
    private let resolvedParser: PackageResolvedParser
    private let resolvedEditor: PackageResolvedEditor

    public init(
        pathUtility: PathUtility,
        xcodebuildRunner: XcodebuildRunner = .init(),
        resolvedParser: PackageResolvedParser = .init(),
        resolvedEditor: PackageResolvedEditor = .init(),
    ) {
        self.pathUtility = pathUtility
        self.xcodebuildRunner = xcodebuildRunner
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
                + "Xcode's 'Update to Latest Package Versions'. A dropped pin that resolution "
                + "does not write back fails the call, and Package.resolved goes back as it was.",
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

        let before = pins(for: container)

        // Package.resolved is a checked-in file. Dropping a pin and then failing to resolve would
        // leave the project silently unpinned, so keep the original bytes and put them back on
        // every failure path.
        let backup = update ? PinsFileBackup(container: container, parser: resolvedParser) : nil

        if update {
            do {
                try lines.append(contentsOf: dropPins(for: container, packageURL: packageURL))
            } catch {
                backup?.restore()
                throw error
            }
        }

        let result: ProcessResult

        do {
            result = try await xcodebuildRunner.resolvePackageDependencies(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                timeout: timeout,
                outputTimeout: arguments.resolveOutputTimeout(
                    default: XcodebuildRunner.deviceOutputTimeout,
                ),
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

            if let backup {
                message += backup.restore()
                    ? "\n\nPackage.resolved was restored to its prior state."
                    : "\n\nWARNING: Package.resolved could not be restored. Its pins may be "
                        + "incomplete. Check the file into review before building."
            }
            throw MCPError.internalError(message)
        }

        let after = pins(for: container)
        let unreplaced = Self.unreplacedPins(before: before, after: after)

        if let backup, !unreplaced.isEmpty {
            throw MCPError.internalError(Self.unreplacedPinsMessage(
                unreplaced, restored: backup.restore()))
        }

        lines.append("Package resolution succeeded.")
        lines.append(contentsOf: changes(from: before, to: after))
        lines.append(DerivedDataScoper.note(
            workspacePath: workspacePath, projectPath: projectPath, destination: destination,
        ))

        return CallTool.Result.text(lines.joined(separator: "\n"))
    }

    // MARK: - Pins

    /// Reads the current pins, keyed by identity. Returns an empty map when no pins file exists.
    private func pins(for container: String) -> [String: ResolvedPin] {
        guard let file = resolvedParser.locate(for: container),
              let parsed = try? resolvedParser.parse(fileAt: file) else { return [:] }
        return Dictionary(parsed.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
    }

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

    /// The failure text for pins resolution left out of the file.
    ///
    /// - Parameters:
    ///   - identities: The packages that lost their pin.
    ///   - restored: Whether the prior pins file went back in place.
    static func unreplacedPinsMessage(_ identities: [String], restored: Bool) -> String {
        var message = "Package resolution succeeded but left "
            + "\(identities.count) package(s) unpinned: "
            + identities.joined(separator: ", ")
            + ". Resolution reused a checkout that already satisfied the requirement, so it wrote "
            + "no pin back and Package.resolved lost the entry."

        message += restored
            ? " Package.resolved was restored to its prior state, so no version moved. Delete the "
                + "package's checkout under DerivedData SourcePackages, then retry."
            : " WARNING: Package.resolved could not be restored and is missing those pins. Recover "
                + "it from version control before building."
        return message
    }

    /// Reports each pin whose version, branch or revision moved.
    private func changes(
        from before: [String: ResolvedPin],
        to after: [String: ResolvedPin],
    ) -> [String] {
        var lines: [String] = []

        for identity in after.keys.sorted() {
            guard let new = after[identity] else { continue }

            guard let old = before[identity] else {
                lines.append("  + \(identity) \(new.stateDescription)")
                continue
            }
            if old.stateDescription != new.stateDescription {
                lines.append("  ~ \(identity) \(old.stateDescription) → \(new.stateDescription)")
            }
        }

        for identity in before.keys.sorted() where after[identity] == nil {
            lines.append("  - \(identity) (no longer pinned)")
        }
        return lines.isEmpty ? ["No pin changed."] : ["Pin changes:"] + lines
    }
}
