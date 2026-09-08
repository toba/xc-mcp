import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Writes the `platformFilters` key on a Copy Files phase entry or on a target dependency.
///
/// A multiplatform target that supports iOS and macOS embeds a macOS-only helper through this key.
/// Without it, the iOS build tries to build and embed a product it cannot produce. Xcode shows the
/// same key as the Platforms column of a build phase's file list.
public struct SetPlatformFiltersTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_platform_filters",
            description:
                "Set or clear the platformFilters key on a Copy Files phase entry (pass file_name) or on a target dependency (pass dependency_name). This is Xcode's Platforms column: a filtered entry is skipped when building for any other platform, which is how a multiplatform target embeds a macOS-only helper. Pass an empty platform_filters array to clear the key and build the entry on every platform. Accepted names: macos, ios, maccatalyst, tvos, watchos, xros, visionos, driverkit.",
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
                            "Name of the target holding the phase entry or the dependency",
                        ),
                    ]),
                    "platform_filters": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Platforms the entry builds for, e.g. ['macos']. An empty array clears the filter.",
                        ),
                        "items": .object(["type": .string("string")]),
                    ]),
                    "file_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the Copy Files phase entry to filter, e.g. 'jig-direct.app'. Matched against the entry's file name, its path, the last path component of its path, and the product name for a Swift package product. Mutually exclusive with dependency_name.",
                        ),
                    ]),
                    "dependency_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target dependency to filter. Mutually exclusive with file_name.",
                        ),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: name of the Copy Files phase, e.g. 'Embed Helpers'. If absent, the phase is located via dst_path or by being the target's only Copy Files phase.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: dstPath of the Copy Files phase. Used to locate phases that have no name.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("platform_filters"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let requested = arguments.getOptionalStringArray("platform_filters")
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and platform_filters are required",
            )
        }

        let fileName = arguments.getNonEmptyString("file_name")
        let dependencyName = arguments.getNonEmptyString("dependency_name")

        guard fileName == nil || dependencyName == nil else {
            throw MCPError.invalidParams(
                "Pass file_name or dependency_name, not both. One call filters one entry.",
            )
        }

        guard fileName != nil || dependencyName != nil else {
            throw MCPError.invalidParams(
                "Pass file_name to filter a Copy Files phase entry, or dependency_name to filter a target dependency",
            )
        }

        let filters = try PlatformFilters.normalize(requested)

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectFilePath = Path(projectURL.path)

            let preimage = PBXProjWriter.preimage(of: projectFilePath)
            let xcodeproj = try XcodeProj(path: projectFilePath)

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { return .text("Target '\(targetName)' not found in project") }

            let object: any PlatformFilterable
            let label: String

            if let fileName {
                let phase = try CopyFilesPhaseLocator.locate(
                    in: target,
                    phaseName: arguments.getString("phase_name"),
                    dstPath: arguments.getString("dst_path"),
                    targetName: targetName,
                )
                let phaseLabel = phase.name ?? ("dstPath=" + (phase.dstPath ?? ""))
                let entries = phase.files ?? []
                let matching = entries.filter { CopyFilesPhaseEntry.matches($0, name: fileName) }

                if matching.isEmpty {
                    let present = entries.map { "  - " + CopyFilesPhaseEntry.label(for: $0) }
                    let listing = present.isEmpty
                        ? "The phase is empty."
                        : "Entries in the phase:\n\(present.joined(separator: "\n"))"
                    return .text(
                        "'\(fileName)' is not in Copy Files phase '\(phaseLabel)' of target '\(targetName)'. \(listing)",
                    )
                }

                if matching.count > 1 {
                    return .text(
                        "'\(fileName)' matches \(matching.count) entries in Copy Files phase '\(phaseLabel)' of target '\(targetName)'. Use a more specific name.",
                    )
                }

                object = matching[0]
                label = "'\(fileName)' in Copy Files phase '\(phaseLabel)'"
            } else if let dependencyName {
                let matching = target.dependencies.filter { Self.matches($0, name: dependencyName) }

                if matching.isEmpty {
                    let present = target.dependencies.map { "  - " + Self.label(for: $0) }
                    let listing = present.isEmpty
                        ? "The target has no dependencies."
                        : "Dependencies of the target:\n\(present.joined(separator: "\n"))"
                    return .text(
                        "Target '\(targetName)' has no dependency named '\(dependencyName)'. \(listing)",
                    )
                }

                if matching.count > 1 {
                    return .text(
                        "Target '\(targetName)' has \(matching.count) dependencies named '\(dependencyName)'. Remove the duplicate first.",
                    )
                }

                object = matching[0]
                label = "dependency '\(dependencyName)'"
            } else {
                // The guards above already refused a call that names neither one.
                throw MCPError.invalidParams("Pass file_name or dependency_name")
            }

            let before = PlatformFilters.describe(PlatformFilters.read(object))
            let changed = PlatformFilters.write(filters, to: object)

            guard changed else {
                return .text(
                    "\(label) of target '\(targetName)' already has platformFilters \(before). No changes made.",
                )
            }

            try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)

            let after = PlatformFilters.describe(filters)
            return .text(
                "Set platformFilters on \(label) of target '\(targetName)' (\(before) -> \(after))",
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Whether a dependency answers to `name`, matching its own name or its target's name.
    private static func matches(_ dependency: PBXTargetDependency, name: String) -> Bool {
        if dependency.name == name { return true }
        if dependency.target?.name == name { return true }
        return dependency.targetProxy?.remoteInfo == name
    }

    /// Names a dependency for result text.
    private static func label(for dependency: PBXTargetDependency) -> String {
        dependency.name ?? dependency.target?.name ?? dependency.targetProxy?.remoteInfo
            ?? dependency.uuid
    }
}
