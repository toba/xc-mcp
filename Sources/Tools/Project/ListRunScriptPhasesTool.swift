import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Lists PBXShellScriptBuildPhase entries across targets.
///
/// Useful for auditing pre/post-build script invocations (Swiftiomatic, SwiftGen,
/// GRDB pre-actions, custom codegen) without grepping project.pbxproj manually.
public struct ListRunScriptPhasesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_run_script_phases",
            description:
                "List every PBXShellScriptBuildPhase across the project's native targets, with each phase's name, position among build phases, input/output paths, sandbox/dependency-tracking flags, and shellScript body. Optionally restrict to a single target or filter by a substring of the shellScript body.",
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
                            "Optional target name to restrict listing to. If omitted, all native targets are scanned.",
                        ),
                    ]),
                    "filter_script": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional substring filter against the shellScript body (case-sensitive). Useful for finding which target runs e.g. 'swiftiomatic' or 'GRDB'.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        let targetFilter: String?
        if case let .string(t) = arguments["target_name"] { targetFilter = t } else {
            targetFilter = nil
        }

        let scriptFilter: String?
        if case let .string(s) = arguments["filter_script"], !s.isEmpty { scriptFilter = s } else {
            scriptFilter = nil
        }

        do {
            let resolvedPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            var lines: [String] = []
            var phaseCount = 0

            let targets = xcodeproj.pbxproj.nativeTargets
                .filter { targetFilter == nil || $0.name == targetFilter }
                .sorted(by: { $0.name < $1.name })

            if let targetFilter, targets.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text: "Target '\(targetFilter)' not found in project",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            for target in targets {
                var targetSection: [String] = []
                for (idx, phase) in target.buildPhases.enumerated() {
                    guard let shell = phase as? PBXShellScriptBuildPhase else { continue }
                    let body = shell.shellScript ?? ""
                    if let scriptFilter, !body.contains(scriptFilter) { continue }
                    phaseCount += 1
                    let name = shell.name ?? "<unnamed>"
                    let shellPath = shell.shellPath ?? "/bin/sh"
                    let inputs = shell.inputPaths
                    let outputs = shell.outputPaths
                    let inputLists = shell.inputFileListPaths ?? []
                    let outputLists = shell.outputFileListPaths ?? []
                    let runOnly = shell.runOnlyForDeploymentPostprocessing
                    let alwaysOOD = shell.alwaysOutOfDate
                    let depFile = shell.dependencyFile ?? "<none>"
                    targetSection.append(
                        "  - phase[\(idx)] '\(name)' (uuid=\(shell.uuid))",
                    )
                    targetSection.append("    shellPath: \(shellPath)")
                    targetSection.append(
                        "    runOnlyForDeploymentPostprocessing=\(runOnly) alwaysOutOfDate=\(alwaysOOD) dependencyFile=\(depFile)",
                    )
                    if !inputs.isEmpty {
                        targetSection.append("    inputs: \(inputs.joined(separator: ", "))")
                    }
                    if !outputs.isEmpty {
                        targetSection.append("    outputs: \(outputs.joined(separator: ", "))")
                    }
                    if !inputLists.isEmpty {
                        targetSection.append(
                            "    inputFileLists: \(inputLists.joined(separator: ", "))",
                        )
                    }
                    if !outputLists.isEmpty {
                        targetSection.append(
                            "    outputFileLists: \(outputLists.joined(separator: ", "))",
                        )
                    }
                    let scriptLines = body.split(
                        omittingEmptySubsequences: false,
                        whereSeparator: \.isNewline,
                    )
                    targetSection.append("    shellScript:")
                    for sl in scriptLines {
                        targetSection.append("      | \(sl)")
                    }
                }
                if !targetSection.isEmpty {
                    lines.append("Target '\(target.name)':")
                    lines.append(contentsOf: targetSection)
                }
            }

            let scope =
                "target=\(targetFilter ?? "*"), filter=\(scriptFilter ?? "<none>")"
            let header =
                "list_run_script_phases in \(projectURL.lastPathComponent) (\(scope)): \(phaseCount) phase\(phaseCount == 1 ? "" : "s")"
            let body = lines.isEmpty ? "  (no matching shell-script phases)" : lines.joined(separator: "\n")

            return CallTool.Result(content: [
                .text(text: "\(header)\n\(body)", annotations: nil, _meta: nil),
            ])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
