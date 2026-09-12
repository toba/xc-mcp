import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Writes the `platformFilters` key on a build phase entry or on a target dependency.
///
/// A multiplatform target that supports iOS and macOS embeds a macOS-only helper through this key,
/// and it links a macOS-only Swift package product through the same key. Without it, the iOS build
/// tries to build a product it cannot produce. Xcode shows the key as the Platforms column of a
/// build phase's file list.
public struct SetPlatformFiltersTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_platform_filters",
            description:
                "Set or clear the platformFilters key on a Copy Files phase entry (pass file_name), on a linked Swift package product in the Frameworks build phase (pass product_name), or on a target dependency (pass dependency_name). This is Xcode's Platforms column: a filtered entry is skipped when building for any other platform, which is how a multiplatform target embeds a macOS-only helper or links a macOS-only package product. Pass an empty platform_filters array to clear the key and build the entry on every platform. Accepted names: macos, ios, maccatalyst, tvos, watchos, xros, visionos, driverkit.",
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
                            "Name of the target holding the phase entry, the linked product, or the dependency",
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
                            "Name of the Copy Files phase entry to filter, e.g. 'jig-direct.app'. Matched against the entry's file name, its path, the last path component of its path, and the product name for a Swift package product. Mutually exclusive with product_name and dependency_name.",
                        ),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of a Swift package product linked in the target's Frameworks build phase, e.g. 'MusupScan'. A framework or a library linked there answers to its file name through the same argument. Mutually exclusive with file_name and dependency_name.",
                        ),
                    ]),
                    "dependency_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target dependency to filter. Mutually exclusive with file_name and product_name.",
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

        let locator = try Locator.parse(from: arguments)
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

            switch locator {
                case let .file(name):
                    let phase = try CopyFilesPhaseLocator.locate(
                        in: target,
                        phaseName: arguments.getNonEmptyString("phase_name"),
                        dstPath: arguments.getString("dst_path"),
                        targetName: targetName,
                    )

                    switch BuildPhaseEntry.resolve(named: name, in: phase, targetName: targetName) {
                        case let .found(match): object = match
                        case let .explained(text): return .text(text)
                    }
                    label = "'\(name)' in Copy Files phase "
                        + "'\(CopyFilesPhaseLocator.label(for: phase))'"

                case let .product(name):
                    guard let phase = target.buildPhases.lazy
                        .compactMap({ $0 as? PBXFrameworksBuildPhase }).first
                    else {
                        return .text(
                            "Target '\(targetName)' has no Frameworks build phase, so it links no product. A plugin product carries no link to filter.",
                        )
                    }

                    switch BuildPhaseEntry.resolve(
                        named: name,
                        in: phase,
                        phaseDescription: "the Frameworks build phase",
                        targetName: targetName,
                    ) {
                        case let .found(match): object = match
                        case let .explained(text): return .text(text)
                    }
                    label = "'\(name)' in the Frameworks build phase"

                case let .dependency(name):
                    switch TargetDependencyEntry.resolve(named: name, in: target) {
                        case let .found(match): object = match
                        case let .explained(text): return .text(text)
                    }
                    label = "dependency '\(name)'"
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

    /// The one entry a call filters
    ///
    /// The three arguments that name an entry are mutually exclusive, so one call carries exactly
    /// one case.
    private enum Locator {
        case file(String)
        case product(String)
        case dependency(String)

        /// The entry the arguments name.
        ///
        /// - Throws: ``MCPError/invalidParams(_:)`` when the arguments name none of the three, or
        ///   more than one.
        static func parse(from arguments: [String: Value]) throws(MCPError) -> Locator {
            var found: [(key: String, locator: Locator)] = []

            if let name = arguments.getNonEmptyString("file_name") {
                found.append(("file_name", .file(name)))
            }

            if let name = arguments.getNonEmptyString("product_name") {
                found.append(("product_name", .product(name)))
            }

            if let name = arguments.getNonEmptyString("dependency_name") {
                found.append(("dependency_name", .dependency(name)))
            }

            switch found.count {
                case 0:
                    throw .invalidParams(
                        "Pass file_name to filter a Copy Files phase entry, product_name to filter a linked Swift package product, or dependency_name to filter a target dependency",
                    )
                case 1: return found[0].locator
                default:
                    throw .invalidParams(
                        "Pass one of file_name, product_name or dependency_name, not \(found.map(\.key).joined(separator: " and ")). One call filters one entry.",
                    )
            }
        }
    }
}
