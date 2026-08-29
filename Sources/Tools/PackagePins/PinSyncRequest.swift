import MCP
import XCMCPCore
import Foundation

/// What a pin sweep is asked to do
///
/// The member list comes from the caller rather than from a directory scan. A scan would hard-code
/// one workspace layout, and it could not express a member that lives outside it.
public struct PinSyncRequest: Sendable {
    /// One package that already carries a published tag
    public struct Update: Sendable, Equatable {
        /// SwiftPM identity of the package
        public let identity: String

        /// The version every member should pin
        public let version: SemanticVersion
    }

    /// Absolute paths to the repositories the sweep may read and write
    public let members: [String]

    /// The packages whose new versions seed the sweep
    public let updates: [Update]

    /// How far a member's own version advances when its pins move
    public let bump: VersionBump

    /// Whether to report the plan without writing, committing, tagging or pushing
    public let dryRun: Bool

    /// Names of members that take a commit but no version bump and no tag
    public let noTag: Set<String>

    /// The remote a tag is pushed to
    public let remote: String

    /// A commit subject that replaces the generated one
    public let messageOverride: String?

    /// Reads the plan from tool arguments, optionally seeded by a JSON file.
    ///
    /// `plan_path` names a file holding the same keys. An argument given inline wins over the file,
    /// so a caller can keep the member list in version control and vary one package per call.
    ///
    /// - Parameter arguments: The tool call arguments.
    /// - Returns: The parsed plan.
    /// - Throws: ``MCPError/invalidParams(_:)`` when a required field is missing or unparsable.
    public static func make(from arguments: [String: Value]) throws(MCPError) -> PinSyncRequest {
        let file = try planFile(at: arguments.getNonEmptyString("plan_path"))

        let memberPaths = arguments.getOptionalStringArray("members") ?? file?.members ?? []
        guard !memberPaths.isEmpty else {
            throw .invalidParams(
                "members is required, either inline or in the file named by plan_path",
            )
        }

        let updates = try parseUpdates(from: arguments, file: file)
        guard !updates.isEmpty else {
            throw .invalidParams(
                "updated is required and must name at least one package and version",
            )
        }

        let bumpName = arguments.getNonEmptyString("bump") ?? file?.bump
            ?? VersionBump.minor.rawValue
        guard let bump = VersionBump(rawValue: bumpName) else {
            throw .invalidParams(
                "Unknown bump: \(bumpName). Expected one of \(VersionBump.allNames)")
        }

        return .init(
            members: memberPaths.map { PathUtility.resolvePath(from: $0) },
            updates: updates,
            bump: bump,
            dryRun: arguments.getOptionalBool("dry_run") ?? file?.dryRun ?? true,
            noTag: Set(arguments.getOptionalStringArray("no_tag") ?? file?.noTag ?? []),
            remote: arguments.getNonEmptyString("remote") ?? file?.remote ?? "origin",
            messageOverride: arguments.getNonEmptyString("message") ?? file?.message,
        )
    }

    /// Reads the `updated` entries from the arguments, falling back to the file.
    private static func parseUpdates(
        from arguments: [String: Value],
        file: PlanFile?,
    ) throws(MCPError) -> [Update] {
        let pairs = try inlinePairs(arguments["updated"])
            ?? (file?.updated ?? []).map { ($0.package, $0.version) }
        var updates: [Update] = []
        updates.reserveCapacity(pairs.count)

        for pair in pairs { try updates.append(update(package: pair.0, version: pair.1)) }
        return updates
    }

    /// Reads the inline `updated` array, or `nil` when the caller sent no array.
    ///
    /// The `nil` case is what lets the plan file supply the entries. An empty inline array means
    /// the caller sent one and named nothing, which ``make(from:)`` refuses.
    private static func inlinePairs(_ value: Value?) throws(MCPError) -> [(String, String)]? {
        guard case let .array(entries) = value else { return nil }
        var pairs: [(String, String)] = []
        pairs.reserveCapacity(entries.count)

        for entry in entries {
            guard case let .object(fields) = entry,
                  case let .string(package) = fields["package"],
                  case let .string(version) = fields["version"]
            else {
                throw .invalidParams(
                    "Each updated entry needs a 'package' string and a 'version' string",
                )
            }
            pairs.append((package, version))
        }
        return pairs
    }

    private static func update(package: String, version: String) throws(MCPError) -> Update {
        guard let parsed = SemanticVersion(version) else {
            throw .invalidParams("version '\(version)' for '\(package)' is not a semantic version")
        }
        return .init(identity: PackageResolvedParser.identity(forURL: package), version: parsed)
    }

    /// Decodes the JSON plan file, or returns `nil` when the caller named none.
    private static func planFile(at path: String?) throws(MCPError) -> PlanFile? {
        guard let path else { return nil }
        let resolved = PathUtility.resolvePath(from: path)

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: resolved))
            return try JSONDecoder().decode(PlanFile.self, from: data)
        } catch {
            throw .invalidParams("Cannot read the plan at \(resolved): \(error)")
        }
    }

    /// The on-disk shape of a plan file, which mirrors the tool's own argument names.
    private struct PlanFile: Decodable {
        struct Update: Decodable {
            let package: String
            let version: String
        }

        let members: [String]?
        let updated: [Update]?
        let bump: String?
        let dryRun: Bool?
        let noTag: [String]?
        let remote: String?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case members, updated, bump, remote, message
            case dryRun = "dry_run"
            case noTag = "no_tag"
        }
    }
}
