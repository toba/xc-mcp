import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListCopyFilesPhases: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "list_copy_files_phases",
            description:
                "List all Copy Files build phases for a target, with each entry's ATTRIBUTES flags and platformFilters. A CodeSignOnCopy entry is re-signed with the embedding target's identity and entitlements. A filtered entry is skipped when building for any other platform. Change an entry's flags with set_copy_files_attributes, and its platforms with set_platform_filters.",
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
                        "description": .string("Name of the target to list phases for"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name")
        else { throw MCPError.invalidParams("project_path and target_name are required") }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            let copyFilesPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }

            if copyFilesPhases.isEmpty {
                return CallTool.Result.text(
                    "No Copy Files build phases found in target '\(targetName)'")
            }

            var output = "Copy Files Build Phases in target '\(targetName)':\n\n"

            for phase in copyFilesPhases {
                let phaseName = phase.name ?? "(unnamed)"
                let destination: String

                if let subfolder = phase.dstSubfolderSpec {
                    destination = destinationString(subfolder)
                } else if let subfolder = phase.dstSubfolder {
                    destination = subfolder.rawValue
                } else {
                    destination = "(unknown)"
                }
                let dstPath = phase.dstPath ?? ""
                let fileCount = phase.files?.count ?? 0

                output += "- \(phaseName)\n"
                output += "  Destination: \(destination)\n"
                if !dstPath.isEmpty { output += "  Subpath: \(dstPath)\n" }
                output += "  Files: \(fileCount)\n"

                for buildFile in phase.files ?? [] {
                    let label = BuildPhaseEntry.label(for: buildFile)
                    let attributes = BuildFileAttributes.describe(BuildFileAttributes.read(
                        buildFile))
                    let filters = PlatformFilters.describe(PlatformFilters.read(buildFile))
                    output += "    - \(label)  attributes: \(attributes)  platforms: \(filters)\n"
                }
                output += "\n"
            }

            return CallTool.Result.text(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw try error.asMCPError()
        }
    }

    private func destinationString(_ subfolder: PBXCopyFilesBuildPhase.SubFolder) -> String {
        switch subfolder {
            case .absolutePath: "Absolute Path"
            case .productsDirectory: "Products Directory"
            case .wrapper: "Wrapper"
            case .executables: "Executables"
            case .resources: "Resources"
            case .javaResources: "Java Resources"
            case .frameworks: "Frameworks"
            case .sharedFrameworks: "Shared Frameworks"
            case .sharedSupport: "Shared Support"
            case .plugins: "Plugins"
            case .other: "Other"
            @unknown default: "Unknown"
        }
    }
}
