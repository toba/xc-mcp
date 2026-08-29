import MCP
import XCMCPCore
import Foundation

/// Raises a version pin through a set of local repositories, transitively.
///
/// One release of a shared package does not reach its dependents on its own. Each dependent states
/// a floor with `from:`, so the new version stays invisible until somebody edits that manifest,
/// tags a release of the dependent, and repeats the edit one layer up. This tool does that walk: it
/// reads the pins each member declares, orders the members so a dependency publishes before its
/// dependents, and raises, commits, tags and pushes each layer in turn.
///
/// The run is all-or-nothing at the boundary that matters. Every member is checked before any
/// member is written, so a dirty working tree or a branch behind its remote refuses the whole sweep
/// instead of leaving half the graph pinned to tags nobody published.
public struct SyncPackagePinsTool: Sendable {
    private let engine: PinSyncEngine

    public init(git: GitRunner = .init(), swift: SwiftRunner = .init()) {
        engine = PinSyncEngine(git: git, swift: swift)
    }

    public func tool() -> Tool {
        .init(
            name: "sync_package_pins",
            description: "Raise a Swift package version pin through a set of local repositories, "
                + "transitively. Reads the pins each member declares (root Package.swift, any "
                + "Package.swift one directory below it, and an Xcode project's remote package "
                + "references), orders the members so a dependency publishes before its "
                + "dependents, then raises each floor, bumps the member's own version, and "
                + "commits, tags and pushes. Every member is checked first: a staged or unstaged "
                + "change, a detached HEAD, a branch behind or ahead of its remote, or a local "
                + "path dependency refuses the whole run with nothing written. Defaults to a dry "
                + "run; pass dry_run false to write.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "members": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Repository roots the sweep may read and write. Each must be a git "
                                + "work-tree root holding either a root Package.swift or exactly "
                                + "one .xcodeproj. A member's identity is its directory name, "
                                + "which is what a package URL's last path component resolves to.",
                        ),
                    ]),
                    "updated": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "package": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Package name or repository URL, such as 'toba-core'",
                                    ),
                                ]),
                                "version": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "The published version every member should pin",
                                    ),
                                ]),
                            ]),
                            "required": .array([.string("package"), .string("version")]),
                        ]),
                        "description": .string(
                            "The packages that already carry a published tag. These seed the "
                                + "sweep; every other member is raised transitively.",
                        ),
                    ]),
                    "plan_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a JSON file holding the same keys as this tool's arguments. "
                                + "An argument given inline wins over the file, so a member list "
                                + "can live in version control while one package varies per call.",
                        ),
                    ]),
                    "bump": .object([
                        "type": .string("string"),
                        "enum": .array(VersionBump.allCases.map { .string($0.rawValue) }),
                        "description": .string(
                            "How far a member's own version advances when its pins move. "
                                + "Defaults to minor.",
                        ),
                    ]),
                    "dry_run": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, report the whole plan and write nothing. Defaults to true, "
                                + "because the run commits, tags and pushes.",
                        ),
                    ]),
                    "no_tag": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Directory names of members that take a commit but no version bump and "
                                + "no tag. An Xcode project member never takes one.",
                        ),
                    ]),
                    "remote": .object([
                        "type": .string("string"),
                        "description": .string("Remote a tag is pushed to. Defaults to origin."),
                    ]),
                    "message": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Commit subject that replaces the generated one on every member.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let request = try PinSyncRequest.make(from: arguments)
            let report = try await engine.run(request)
            return CallTool.Result.text(report)
        } catch {
            throw try error.asMCPError()
        }
    }
}
