import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Sets incremental-build metadata on an existing Run Script (PBXShellScriptBuildPhase).
///
/// A run-script phase with no declared outputs is always considered out-of-date and
/// re-runs on every incremental build. Declaring `input_paths` + `output_paths` (or a
/// `dependency_file`) lets Xcode's build graph skip the phase when its inputs are
/// unchanged. This is the writer counterpart to `list_run_script_phases`, which can
/// read these fields but not modify them.
///
/// Only fields explicitly present in the arguments are modified; omitted fields are
/// left untouched. Passing an empty array clears a paths field; passing an empty
/// string for `dependency_file` clears it.
public struct SetRunScriptPhaseIOTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "set_run_script_phase_io",
            description:
                "Set incremental-build metadata on an existing Run Script (PBXShellScriptBuildPhase): input_paths, output_paths, input_file_list_paths (.xcfilelist), output_file_list_paths (.xcfilelist), dependency_file (.d), and always_out_of_date. Declaring inputs/outputs (or a dependency file) lets Xcode skip the phase when its inputs are unchanged, instead of re-running it every build. Only fields present in the request are modified; an empty array clears a paths field and an empty string clears dependency_file.",
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
                        "description": .string("Name of the target containing the phase"),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the Run Script phase to modify. Matches PBXShellScriptBuildPhase.name; if unnamed, falls back to matching the default 'ShellScript'.",
                        ),
                    ]),
                    "input_paths": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Input file paths (build-setting variables like $(SRCROOT) allowed). Pass [] to clear. Omit to leave unchanged.",
                        ),
                    ]),
                    "output_paths": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Output file paths declared by the script. Pass [] to clear. Omit to leave unchanged.",
                        ),
                    ]),
                    "input_file_list_paths": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Paths to .xcfilelist files enumerating inputs. Pass [] to clear. Omit to leave unchanged.",
                        ),
                    ]),
                    "output_file_list_paths": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Paths to .xcfilelist files enumerating outputs. Pass [] to clear. Omit to leave unchanged.",
                        ),
                    ]),
                    "dependency_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a Makefile-style .d dependency file the script writes for discovered-dependency tracking. Pass \"\" to clear. Omit to leave unchanged.",
                        ),
                    ]),
                    "always_out_of_date": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, Xcode runs the phase on every build regardless of inputs/outputs (\"Based on dependency analysis\" unchecked). Set false to allow skipping. Omit to leave unchanged.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("phase_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(phaseName) = arguments["phase_name"]
        else {
            throw MCPError.invalidParams("project_path, target_name, and phase_name are required")
        }

        // Reject a call that changes nothing so the caller gets a clear signal
        // rather than a misleading "success" that touched no fields.
        let ioKeys = [
            "input_paths", "output_paths", "input_file_list_paths",
            "output_file_list_paths", "dependency_file", "always_out_of_date",
        ]
        guard ioKeys.contains(where: { arguments[$0] != nil }) else {
            throw MCPError.invalidParams(
                "At least one of input_paths, output_paths, input_file_list_paths, output_file_list_paths, dependency_file, or always_out_of_date must be provided",
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(
                    content: [.text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            }

            // Find the run-script phase by name. Treat a nil name as the
            // implicit default "ShellScript" so callers can target unnamed phases.
            let matchingIndices = target.buildPhases.enumerated().compactMap {
                index, phase -> Int? in
                guard let shell = phase as? PBXShellScriptBuildPhase else { return nil }
                let resolvedName = shell.name ?? "ShellScript"
                return resolvedName == phaseName ? index : nil
            }

            guard let phaseIndex = matchingIndices.first else {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Run Script phase '\(phaseName)' not found in target '\(targetName)'",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            if matchingIndices.count > 1 {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Multiple Run Script phases named '\(phaseName)' found in target '\(targetName)'; rename them to disambiguate before modification",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            guard let shell = target.buildPhases[phaseIndex] as? PBXShellScriptBuildPhase else {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Run Script phase '\(phaseName)' not found in target '\(targetName)'",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            var changes: [String] = []

            if let paths = stringArray(from: arguments["input_paths"]) {
                shell.inputPaths = paths
                changes.append("inputPaths=\(describe(paths))")
            }
            if let paths = stringArray(from: arguments["output_paths"]) {
                shell.outputPaths = paths
                changes.append("outputPaths=\(describe(paths))")
            }
            if let paths = stringArray(from: arguments["input_file_list_paths"]) {
                // An empty file-list array is stored as nil so the field is omitted
                // from project.pbxproj rather than serialized as an empty list.
                shell.inputFileListPaths = paths.isEmpty ? nil : paths
                changes.append("inputFileListPaths=\(describe(paths))")
            }
            if let paths = stringArray(from: arguments["output_file_list_paths"]) {
                shell.outputFileListPaths = paths.isEmpty ? nil : paths
                changes.append("outputFileListPaths=\(describe(paths))")
            }
            if case let .string(depFile) = arguments["dependency_file"] {
                shell.dependencyFile = depFile.isEmpty ? nil : depFile
                changes.append("dependencyFile=\(depFile.isEmpty ? "<none>" : depFile)")
            }
            if case let .bool(alwaysOOD) = arguments["always_out_of_date"] {
                shell.alwaysOutOfDate = alwaysOOD
                changes.append("alwaysOutOfDate=\(alwaysOOD)")
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(text:
                        "Updated Run Script phase '\(phaseName)' in target '\(targetName)': \(changes.joined(separator: ", "))",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to set run script phase I/O: \(error.localizedDescription)",
            )
        }
    }

    /// Extracts a `[String]` from an array argument, or nil when the key was absent.
    /// An empty array is preserved (used to clear a field); non-string elements are dropped.
    private func stringArray(from value: Value?) -> [String]? {
        guard case let .array(items) = value else { return nil }
        return items.compactMap { if case let .string(s) = $0 { return s } else { return nil } }
    }

    private func describe(_ paths: [String]) -> String {
        paths.isEmpty ? "<cleared>" : "[\(paths.joined(separator: ", "))]"
    }
}
