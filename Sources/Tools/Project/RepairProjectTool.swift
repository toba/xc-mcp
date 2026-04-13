import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// MCP tool for repairing common Xcode project issues after migration.
///
/// Fixes problems introduced by Xcode auto-migration (e.g., objectVersion 100):
/// - Removes build files with null file references
/// - Removes orphaned `PBXBuildFile` entries not in any build phase
/// - Reports what was fixed so the caller can verify
public struct RepairProjectTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "repair_project",
            description: """
            Repair common Xcode project issues after migration. \
            Removes null build file references, orphaned PBXBuildFile entries, \
            and other artifacts left by Xcode auto-migration.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file",
                        ),
                    ]),
                    "dry_run": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Report what would be fixed without making changes (default: false)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        let dryRun: Bool
        if case let .bool(dry) = arguments["dry_run"] {
            dryRun = dry
        } else {
            dryRun = false
        }

        let resolvedPath: String
        do {
            resolvedPath = try pathUtility.resolvePath(from: projectPath)
        } catch {
            throw MCPError.invalidParams("Invalid project path: \(error)")
        }

        let path = Path(resolvedPath)
        let xcodeproj: XcodeProj
        do {
            xcodeproj = try XcodeProj(path: path)
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }

        var fixes = [String]()
        let pbxproj = xcodeproj.pbxproj
        let targets = pbxproj.nativeTargets

        // --- Remove null file references from build phases ---
        for target in targets {
            for phase in target.buildPhases {
                guard let files = phase.files else { continue }
                let nullFiles = files.filter { $0.file == nil && $0.product == nil }
                if !nullFiles.isEmpty {
                    let phaseName = phaseName(for: phase)
                    fixes.append(
                        "Removed \(nullFiles.count) null build file\(nullFiles.count == 1 ? "" : "s") from \(target.name)/\(phaseName)",
                    )
                    if !dryRun {
                        phase.files = files.filter { $0.file != nil || $0.product != nil }
                        for nullFile in nullFiles {
                            pbxproj.delete(object: nullFile)
                        }
                    }
                }
            }
        }

        // --- Remove orphaned PBXBuildFile entries ---
        var referencedBuildFileIDs = Set<ObjectIdentifier>()
        for target in targets {
            for phase in target.buildPhases {
                for buildFile in phase.files ?? [] {
                    referencedBuildFileIDs.insert(ObjectIdentifier(buildFile))
                }
            }
        }
        let orphans = pbxproj.buildFiles.filter {
            !referencedBuildFileIDs.contains(ObjectIdentifier($0))
        }
        if !orphans.isEmpty {
            fixes.append(
                "Removed \(orphans.count) orphaned PBXBuildFile\(orphans.count == 1 ? "" : "s") not in any build phase",
            )
            if !dryRun {
                for orphan in orphans {
                    pbxproj.delete(object: orphan)
                }
            }
        }

        // --- Write if changes were made ---
        if !fixes.isEmpty, !dryRun {
            do {
                try PBXProjWriter.write(xcodeproj, to: path)
            } catch {
                throw MCPError.internalError(
                    "Failed to write repaired project: \(error.localizedDescription)",
                )
            }
        }

        // --- Format output ---
        var output = [String]()
        if dryRun {
            output.append("## Dry Run — no changes written\n")
        }

        if fixes.isEmpty {
            output.append("No issues found in \(resolvedPath).")
        } else {
            output.append("## Repairs\(dryRun ? " (would apply)" : "")\n")
            for fix in fixes {
                output.append("- \(fix)")
            }
            output.append("")
            output.append(
                dryRun
                    ? "\(fixes.count) fix\(fixes.count == 1 ? "" : "es") available. Run without dry_run to apply."
                    : "\(fixes.count) fix\(fixes.count == 1 ? "" : "es") applied to \(resolvedPath).",
            )
        }

        return CallTool.Result(content: [.text(
            text: output.joined(separator: "\n"),
            annotations: nil,
            _meta: nil,
        )])
    }

    private func phaseName(for phase: PBXBuildPhase) -> String {
        if let name = phase.name() { return name }
        switch phase {
            case is PBXSourcesBuildPhase: return "Sources"
            case is PBXFrameworksBuildPhase: return "Frameworks"
            case is PBXResourcesBuildPhase: return "Resources"
            case is PBXHeadersBuildPhase: return "Headers"
            case is PBXCopyFilesBuildPhase: return "Copy Files"
            default: return "Build Phase"
        }
    }
}
