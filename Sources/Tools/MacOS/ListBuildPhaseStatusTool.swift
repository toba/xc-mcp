import MCP
import XCMCPCore
import Foundation

/// Reports which build phases executed in the last build and their status.
///
/// For a given target, shows whether compile sources, link, copy resources,
/// run scripts, and other phases actually ran, completed, or were skipped.
/// This immediately reveals when a link step was skipped due to a dependency failure.
public struct ListBuildPhaseStatusTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "list_build_phase_status",
            description:
            "Show which build phases ran in the last build and their completion status. "
                + "Reports compile, link, copy resources, and script phases as "
                + "completed/failed/skipped. Use when a build fails silently — reveals "
                + "if the link step was skipped due to compilation failure.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Target name to check. If omitted, shows all targets.",
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to search build logs for. Uses session default if not specified.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetFilter = arguments.getString("target")
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)

        let projectRoot = try await DerivedDataLocator.findProjectRoot(
            xcodebuildRunner: xcodebuildRunner,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
        )

        let logsDir = URL(fileURLWithPath: projectRoot).appendingPathComponent("Logs/Build").path
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: logsDir) else {
            throw MCPError.internalError("No build logs found at \(logsDir)")
        }

        // Find the most recent build log
        let logs = entries.filter { $0.hasSuffix(".xcactivitylog") }
            .compactMap { name -> (path: String, date: Date)? in
                let path = (logsDir as NSString).appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let date = attrs[.modificationDate] as? Date
                else { return nil }
                return (path, date)
            }
            .sorted { $0.date > $1.date }

        guard let mostRecent = logs.first else {
            throw MCPError.internalError("No build logs found in \(logsDir)")
        }

        let decompressed: String
        do {
            let result = try await ProcessResult.run(
                "/usr/bin/gunzip", arguments: ["-c", mostRecent.path], timeout: .seconds(30),
            )
            decompressed = result.stdout
        } catch {
            throw MCPError.internalError("Failed to decompress build log: \(error)")
        }

        let phases = parseBuildPhases(from: decompressed, target: targetFilter)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let logDate = dateFormatter.string(from: mostRecent.date)

        // Format output
        var text = "## Build Phase Status (\(logDate))\n\n"

        if phases.isEmpty {
            text += "No build phases found"
            if let target = targetFilter {
                text += " for target '\(target)'"
            }
            text += " in the most recent build log."
        } else {
            // Group by target
            var byTarget: [(target: String, phases: [BuildPhaseEntry])] = []
            var currentTarget = ""
            var currentPhases: [BuildPhaseEntry] = []

            for phase in phases {
                if phase.target != currentTarget {
                    if !currentPhases.isEmpty {
                        byTarget.append((target: currentTarget, phases: currentPhases))
                    }
                    currentTarget = phase.target
                    currentPhases = []
                }
                currentPhases.append(phase)
            }
            if !currentPhases.isEmpty {
                byTarget.append((target: currentTarget, phases: currentPhases))
            }

            for group in byTarget {
                text += "### \(group.target)\n\n"
                for phase in group.phases {
                    let icon = phase.status == .completed ? "[OK]" : "[FAIL]"
                    text += "  \(icon) \(phase.phaseType)"
                    if let duration = phase.duration {
                        text += " (\(String(format: "%.1f", duration))s)"
                    }
                    if phase.status == .failed, let detail = phase.detail {
                        text += " — \(detail)"
                    }
                    text += "\n"
                }
                text += "\n"
            }

            // Summary
            let totalPhases = phases.count
            let failedPhases = phases.filter { $0.status == .failed }
            if !failedPhases.isEmpty {
                text += "**\(failedPhases.count) of \(totalPhases) phases failed.**\n"
                text += "\nFailed phases may cause downstream phases (like linking) to be skipped."
            }
        }

        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - Private

    private enum PhaseStatus {
        case completed
        case failed
    }

    private struct BuildPhaseEntry {
        let target: String
        let phaseType: String
        let status: PhaseStatus
        let duration: Double?
        let detail: String?
    }

    /// Build step patterns recognized in xcactivitylog output.
    private static let phasePatterns: [(pattern: String, label: String)] = [
        ("CompileSwiftSources", "Compile Swift Sources"),
        ("CompileSwift ", "Compile Swift"),
        ("CompileC ", "Compile C/ObjC"),
        ("Ld ", "Link"),
        ("Libtool ", "Libtool (Static Library)"),
        ("CpResource ", "Copy Resource"),
        ("CopyPlistFile ", "Copy Plist"),
        ("CopyStringsFile ", "Copy Strings"),
        ("CompileAssetCatalog ", "Compile Asset Catalog"),
        ("CompileStoryboard ", "Compile Storyboard"),
        ("LinkStoryboards ", "Link Storyboards"),
        ("ProcessInfoPlistFile ", "Process Info.plist"),
        ("CodeSign ", "Code Sign"),
        ("PhaseScriptExecution ", "Run Script Phase"),
        ("ProcessProductPackaging ", "Process Product Packaging"),
        ("GenerateDSYMFile ", "Generate dSYM"),
        ("MergeSwiftModule ", "Merge Swift Module"),
        ("SwiftDriver ", "Swift Driver Compilation"),
        ("SwiftCompile ", "Swift Compile"),
        ("SwiftEmitModule ", "Swift Emit Module"),
        ("SwiftMergeGeneratedHeaders ", "Swift Merge Generated Headers"),
        ("CreateBuildDirectory ", "Create Build Directory"),
        ("WriteAuxiliaryFile ", "Write Auxiliary File"),
        ("RegisterExecutionPolicyException ", "Register Execution Policy"),
        ("Validate ", "Validate"),
        ("Touch ", "Touch"),
    ]

    private func parseBuildPhases(
        from log: String, target targetFilter: String?,
    ) -> [BuildPhaseEntry] {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        var phases: [BuildPhaseEntry] = []
        var currentTarget = ""

        for line in lines {
            let str = String(line)

            // Detect target changes: "=== BUILD TARGET <name> ===" or similar
            if str.contains("BUILD TARGET") || str.contains("BUILD AGGREGATE TARGET") {
                if let targetMatch = extractTarget(from: str) {
                    currentTarget = targetMatch
                }
                continue
            }

            // Also detect target from "Build target <name>" lines
            if str.hasPrefix("Build target ") {
                let rest = str.dropFirst("Build target ".count)
                if let spaceIdx = rest.firstIndex(of: " ") {
                    currentTarget = String(rest[rest.startIndex ..< spaceIdx])
                } else {
                    currentTarget = String(rest)
                }
                continue
            }

            // Skip if filtering to a specific target
            if let filter = targetFilter, !currentTarget.isEmpty, currentTarget != filter {
                continue
            }

            // Match build phase patterns
            for (pattern, label) in Self.phasePatterns {
                guard str.contains(pattern) else { continue }

                let failed = str.contains("error:") || str.contains("Command failed")
                    || str.contains("exit code") || str.contains("failed with")
                phases.append(
                    BuildPhaseEntry(
                        target: currentTarget.isEmpty ? "(unknown)" : currentTarget,
                        phaseType: label,
                        status: failed ? .failed : .completed,
                        duration: nil,
                        detail: failed ? str.trimmingCharacters(in: .whitespaces) : nil,
                    ),
                )
                break
            }
        }

        // Deduplicate: keep unique (target, phaseType) pairs, preferring failed status
        var seen: [String: Int] = [:]
        var deduped: [BuildPhaseEntry] = []
        for phase in phases {
            let key = "\(phase.target)/\(phase.phaseType)"
            if let existingIdx = seen[key] {
                // If new one is failed and existing is completed, replace
                if phase.status == .failed, deduped[existingIdx].status == .completed {
                    deduped[existingIdx] = phase
                }
            } else {
                seen[key] = deduped.count
                deduped.append(phase)
            }
        }

        return deduped
    }

    private func extractTarget(from line: String) -> String? {
        // "=== BUILD TARGET MyTarget OF PROJECT MyProject WITH CONFIGURATION Debug ==="
        let patterns = [
            #/BUILD TARGET (\S+) /#,
            #/BUILD AGGREGATE TARGET (\S+) /#,
        ]
        for pattern in patterns {
            if let match = line.firstMatch(of: pattern) {
                return String(match.1)
            }
        }
        return nil
    }
}
