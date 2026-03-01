import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ValidateProjectTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "validate_project",
            description: """
            Validate an Xcode project for common configuration issues. \
            Checks embed phase settings, framework link/embed consistency, \
            and target dependency completeness.
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
                ]),
                "required": .array([.string("project_path")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        let resolvedPath: String
        do {
            resolvedPath = try pathUtility.resolvePath(from: projectPath)
        } catch {
            throw MCPError.invalidParams("Invalid project path: \(error)")
        }

        let xcodeproj: XcodeProj
        do {
            xcodeproj = try XcodeProj(path: Path(resolvedPath))
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }

        let targets = xcodeproj.pbxproj.nativeTargets
        var output = [String]()
        var totalErrors = 0
        var totalWarnings = 0

        // Build a map of target name → product name for dependency checks
        var targetProductNames = [String: String]()
        for target in targets {
            if let productName = target.productNameWithExtension() ?? target.product?.path {
                targetProductNames[target.name] = productName
            }
        }

        for target in targets {
            var diagnostics = [Diagnostic]()

            let copyFilesPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            let frameworksPhase = target.buildPhases
                .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase

            // --- Embed phase validation ---
            checkEmbedPhases(copyFilesPhases, diagnostics: &diagnostics)

            // --- Framework consistency ---
            let linkedNames = frameworkNames(from: frameworksPhase)
            let embeddedNames = embeddedFrameworkNames(from: copyFilesPhases)
            checkFrameworkConsistency(
                linked: linkedNames, embedded: embeddedNames, diagnostics: &diagnostics,
            )

            // --- Dependency completeness ---
            checkDependencyCompleteness(
                target: target, xcodeproj: xcodeproj,
                targetProductNames: targetProductNames, diagnostics: &diagnostics,
            )

            // --- Summary info for this target ---
            let matchedCount = linkedNames.intersection(embeddedNames).count
            if matchedCount > 0 {
                diagnostics.append(
                    Diagnostic(
                        .info,
                        "\(matchedCount) framework\(matchedCount == 1 ? "" : "s") linked and embedded correctly",
                    ),
                )
            }

            if !diagnostics.isEmpty {
                output.append("## Target: \(target.name)\n")
                for diag in diagnostics {
                    output.append(diag.formatted)
                    if diag.severity == .error { totalErrors += 1 }
                    if diag.severity == .warning { totalWarnings += 1 }
                }
                output.append("")
            }
        }

        // Summary
        if totalErrors == 0, totalWarnings == 0 {
            output.append("No issues found in \(resolvedPath).")
        } else {
            var parts = [String]()
            if totalErrors >
                0 { parts.append("\(totalErrors) error\(totalErrors == 1 ? "" : "s")") }
            if totalWarnings > 0 {
                parts.append("\(totalWarnings) warning\(totalWarnings == 1 ? "" : "s")")
            }
            output.append("## Summary: \(parts.joined(separator: ", "))")
        }

        return CallTool.Result(content: [.text(output.joined(separator: "\n"))])
    }

    // MARK: - Embed Phase Checks

    private func checkEmbedPhases(
        _ phases: [PBXCopyFilesBuildPhase],
        diagnostics: inout [Diagnostic],
    ) {
        for phase in phases {
            let phaseName = phase.name ?? "(unnamed)"

            // Check destination on phases named "Embed Frameworks"
            if phaseName.contains("Embed Frameworks"),
               phase.dstSubfolderSpec == nil,
               phase.dstSubfolder != .frameworks
            {
                diagnostics.append(
                    Diagnostic(
                        .error,
                        "Embed phase \"\(phaseName)\" has dstSubfolder=None (should be Frameworks)",
                    ),
                )
            }

            // Empty copy-files phases
            if (phase.files ?? []).isEmpty {
                diagnostics.append(
                    Diagnostic(.warning, "Copy-files phase \"\(phaseName)\" has zero files"),
                )
            }
        }

        // Duplicate framework in multiple copy-files phases
        var seenFiles = [String: String]() // filename → first phase name
        for phase in phases {
            let phaseName = phase.name ?? "(unnamed)"
            for buildFile in phase.files ?? [] {
                guard let fileRef = buildFile.file else { continue }
                let name = fileRef.path ?? fileRef.name ?? "(unknown)"
                if let firstPhase = seenFiles[name] {
                    diagnostics.append(
                        Diagnostic(
                            .error,
                            "\(name) appears in both \"\(firstPhase)\" and \"\(phaseName)\"",
                        ),
                    )
                } else {
                    seenFiles[name] = phaseName
                }
            }
        }
    }

    // MARK: - Framework Consistency

    private func frameworkNames(from phase: PBXFrameworksBuildPhase?) -> Set<String> {
        guard let files = phase?.files else { return [] }
        var names = Set<String>()
        for buildFile in files {
            if let fileRef = buildFile.file {
                if let name = fileRef.path ?? fileRef.name {
                    names.insert(name)
                }
            }
        }
        return names
    }

    private func embeddedFrameworkNames(from phases: [PBXCopyFilesBuildPhase]) -> Set<String> {
        var names = Set<String>()
        for phase in phases
            where phase.dstSubfolderSpec == .frameworks || phase.dstSubfolder == .frameworks
        {
            for buildFile in phase.files ?? [] {
                if let fileRef = buildFile.file {
                    if let name = fileRef.path ?? fileRef.name {
                        names.insert(name)
                    }
                }
            }
        }
        return names
    }

    private func checkFrameworkConsistency(
        linked: Set<String>,
        embedded: Set<String>,
        diagnostics: inout [Diagnostic]
    ) {
        // Linked but not embedded (skip system frameworks)
        for name in linked.sorted() where !embedded.contains(name) {
            if !isSystemFramework(name) {
                diagnostics.append(
                    Diagnostic(.warning, "\(name) linked but not embedded"),
                )
            }
        }

        // Embedded but not linked
        for name in embedded.sorted() where !linked.contains(name) {
            diagnostics.append(
                Diagnostic(.warning, "\(name) embedded but not linked"),
            )
        }
    }

    private func isSystemFramework(_ name: String) -> Bool {
        // System frameworks use .sdkRoot source tree, but at the name level
        // we can heuristic: system frameworks live under System/Library paths
        // or are well-known SDK frameworks. For this check, we skip frameworks
        // that don't end in .framework (e.g. .tbd, .dylib) since those are always system.
        if !name.hasSuffix(".framework") {
            return true
        }
        return false
    }

    // MARK: - Dependency Completeness

    private func checkDependencyCompleteness(
        target: PBXNativeTarget,
        xcodeproj _: XcodeProj,
        targetProductNames: [String: String],
        diagnostics: inout [Diagnostic],
    ) {
        let frameworksPhase = target.buildPhases
            .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase

        let linkedFiles = frameworksPhase?.files ?? []

        // Build set of dependency target names
        let dependencyTargetNames = Set(
            target.dependencies.compactMap { $0.target?.name },
        )

        // Build set of product names that are linked
        let linkedProductNames = Set(
            linkedFiles.compactMap { $0.file?.path ?? $0.file?.name },
        )

        // Check: target links a product from another target but has no dependency
        for (depTargetName, productName) in targetProductNames {
            if depTargetName == target.name { continue }
            if linkedProductNames.contains(productName),
               !dependencyTargetNames.contains(depTargetName)
            {
                diagnostics.append(
                    Diagnostic(
                        .warning,
                        "Links \(productName) from \(depTargetName) but has no target dependency",
                    ),
                )
            }
        }

        // Check: target has dependency but doesn't link the product
        for dep in target.dependencies {
            guard let depTarget = dep.target else { continue }
            if let productName = targetProductNames[depTarget.name],
               !linkedProductNames.contains(productName)
            {
                diagnostics.append(
                    Diagnostic(
                        .info,
                        "Has dependency on \(depTarget.name) but does not link \(productName)",
                    ),
                )
            }
        }
    }
}

// MARK: - Diagnostic Model

extension ValidateProjectTool {
    enum Severity {
        case error, warning, info

        var label: String {
            switch self {
                case .error: return "[error]"
                case .warning: return "[warn] "
                case .info: return "[info] "
            }
        }
    }

    struct Diagnostic {
        let severity: Severity
        let message: String

        init(_ severity: Severity, _ message: String) {
            self.severity = severity
            self.message = message
        }

        var formatted: String {
            "\(severity.label) \(message)"
        }
    }
}
