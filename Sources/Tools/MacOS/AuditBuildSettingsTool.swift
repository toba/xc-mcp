import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Read-only "recommend" pass over resolved build settings, flagging known incremental-build
/// anti-patterns (whole-module in Debug, dSYM in Debug, all-arch builds, explicit-modules off, …)
/// plus run-script phases with no output paths that re-run every incremental build.
///
/// Advisory only — mirrors the review-before-apply stance: it never mutates the project. On a
/// well-configured Debug build it returns near-empty, so a non-empty result is a signal worth
/// acting on.
public struct AuditBuildSettingsTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager
    private let pathUtility: PathUtility

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        sessionManager: SessionManager,
        pathUtility: PathUtility,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        .init(
            name: "audit_build_settings",
            description: "Audit resolved build settings for known incremental-build anti-patterns: "
                + "whole-module compilation in Debug, dwarf-with-dsym in Debug, ONLY_ACTIVE_ARCH "
                + "off, optimization enabled in Debug, explicit modules / compilation caching off, "
                + "and run-script phases with no output paths (which re-run every build). Read-only "
                + "and advisory — reports recommendations without applying them. Returns near-empty "
                + "on a well-configured project.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
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
                            "The scheme to inspect. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration to resolve settings for. Defaults to Debug — the "
                                + "incremental-build anti-patterns are Debug-specific.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments) ?? "Debug"

        let settingsResult = try await xcodebuildRunner.showBuildSettings(
            projectPath: projectPath, workspacePath: workspacePath,
            scheme: scheme, configuration: configuration,
            destination: XcodebuildRunner.macOSDestination,
        )
        let settings = BuildSettingExtractor.parseSettings(from: settingsResult.stdout)

        var findings = Self.auditSettings(settings, configuration: configuration)

        // Best-effort run-script scan: only .xcodeproj projects can be opened directly.
        if let projectPath,
           projectPath.hasSuffix(".xcodeproj"),
           let scriptFindings = try? scanRunScriptPhases(projectPath: projectPath)
        {
            findings.append(contentsOf: scriptFindings)
        }

        let text = Self.formatReport(
            findings: findings, scheme: scheme, configuration: configuration,
        )
        return CallTool.Result.text(text)
    }

    // MARK: - Settings audit

    enum Severity: Int, Sendable {
        case warning = 0
        case info = 1

        var label: String {
            switch self {
                case .warning: "warning"
                case .info: "info"
            }
        }
    }

    struct Finding: Sendable, Equatable {
        let severity: Severity
        let title: String
        let detail: String
        let recommendation: String

        static func == (lhs: Finding, rhs: Finding) -> Bool {
            lhs.title == rhs.title && lhs.detail == rhs.detail
        }
    }

    /// True when the resolved settings describe a debug/development configuration. Whole-module and
    /// `-O` are *correct* for Release, so the incremental-focused checks must not fire there.
    static func isDebugConfiguration(_ settings: [String: String], configuration: String) -> Bool {
        if configuration.caseInsensitiveCompare("Debug") == .orderedSame { return true }
        if let conditions = settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
           conditions.split(separator: " ").contains("DEBUG") { return true }
        return false
    }

    static func auditSettings(
        _ settings: [String: String],
        configuration: String,
    ) -> [Finding] {
        var findings: [Finding] = []
        guard isDebugConfiguration(settings, configuration: configuration) else { return findings }

        if settings["SWIFT_COMPILATION_MODE"] == "wholemodule"
            || settings["SWIFT_WHOLE_MODULE_OPTIMIZATION"] == "YES"
        {
            findings.append(Finding(
                severity: .warning, title: "Whole-module compilation in Debug",
                detail: "SWIFT_COMPILATION_MODE is whole-module, so every incremental build "
                    + "recompiles the entire module.",
                recommendation: "Set SWIFT_COMPILATION_MODE = incremental for the Debug "
                    + "configuration.",
            ))
        }

        if let opt = settings["SWIFT_OPTIMIZATION_LEVEL"], opt != "-Onone" {
            findings.append(Finding(
                severity: .warning, title: "Swift optimization enabled in Debug",
                detail: "SWIFT_OPTIMIZATION_LEVEL is \(opt); optimizing Debug builds slows "
                    + "compilation with no debugging benefit.",
                recommendation: "Set SWIFT_OPTIMIZATION_LEVEL = -Onone for Debug.",
            ))
        }

        if settings["DEBUG_INFORMATION_FORMAT"] == "dwarf-with-dsym" {
            findings.append(Finding(
                severity: .warning, title: "dSYM generation in Debug",
                detail: "DEBUG_INFORMATION_FORMAT is dwarf-with-dsym; generating a dSYM on every "
                    + "Debug build adds link-time cost that's only needed for release symbolication.",
                recommendation: "Set DEBUG_INFORMATION_FORMAT = dwarf for Debug.",
            ))
        }

        if settings["ONLY_ACTIVE_ARCH"] == "NO" {
            findings.append(Finding(
                severity: .warning, title: "Building all architectures in Debug",
                detail:
                    "ONLY_ACTIVE_ARCH is NO, so Debug builds compile every architecture instead "
                    + "of just the active one.",
                recommendation: "Set ONLY_ACTIVE_ARCH = YES for Debug.",
            ))
        }

        // Explicit modules / compilation caching only flagged when explicitly disabled — an absent
        // value may be the Xcode default, and flagging it would add noise.
        if settings["SWIFT_ENABLE_EXPLICIT_MODULES"] == "NO" {
            findings.append(Finding(
                severity: .info, title: "Explicit modules disabled",
                detail: "SWIFT_ENABLE_EXPLICIT_MODULES is NO; explicit modules improve incremental "
                    + "caching and parallelism.",
                recommendation: "Set SWIFT_ENABLE_EXPLICIT_MODULES = YES.",
            ))
        }

        if settings["EAGER_LINKING"] == "NO" {
            findings.append(Finding(
                severity: .info, title: "Eager linking disabled",
                detail: "EAGER_LINKING is NO; enabling it lets dependent targets link before their "
                    + "dependencies finish, shortening the critical path on multi-framework "
                    + "projects.", recommendation: "Set EAGER_LINKING = YES.",
            ))
        }

        return findings
    }

    // MARK: - Run-script phase scan

    private func scanRunScriptPhases(projectPath: String) throws -> [Finding] {
        let resolvedPath = try pathUtility.resolvePath(from: projectPath)
        let xcodeproj = try XcodeProj(path: Path(resolvedPath))
        var findings: [Finding] = []

        for target in xcodeproj.pbxproj.nativeTargets.sorted(by: { $0.name < $1.name }) {
            for phase in target.buildPhases {
                guard let shell = phase as? PBXShellScriptBuildPhase else { continue }
                // Post-processing-only phases run on install/archive, not on incremental builds.
                if shell.runOnlyForDeploymentPostprocessing { continue }
                let hasOutputs = !shell.outputPaths.isEmpty
                    || !(shell.outputFileListPaths ?? []).isEmpty
                if hasOutputs { continue }

                let name = shell.name ?? "<unnamed>"
                findings.append(Finding(
                    severity: .warning, title: "Run-script phase with no output paths",
                    detail: "Target '\(target.name)' phase '\(name)' declares no output files, so "
                        + "Xcode treats it as always-out-of-date and re-runs it on every "
                        + "incremental build.",
                    recommendation: "Declare output paths (or an output file list) so Xcode can "
                        + "skip the phase when inputs are unchanged.",
                ))
            }
        }
        return findings
    }

    // MARK: - Formatting

    static func formatReport(
        findings: [Finding],
        scheme: String,
        configuration: String,
    ) -> String {
        var text = "## Build Settings Audit\n\n"
        text += "**Scheme:** \(scheme)  **Configuration:** \(configuration)\n\n"

        guard !findings.isEmpty else {
            text += "No incremental-build anti-patterns detected. Settings look optimal.\n"
            return text
        }

        let sorted = findings.sorted { $0.severity.rawValue < $1.severity.rawValue }
        let warnings = sorted.count(where: { $0.severity == .warning })
        text += "\(findings.count) finding\(findings.count == 1 ? "" : "s")"
        if warnings > 0 { text += " (\(warnings) warning\(warnings == 1 ? "" : "s"))" }
        text += ":\n\n"

        for finding in sorted {
            text += "### [\(finding.severity.label)] \(finding.title)\n"
            text += "\(finding.detail)\n"
            text += "→ \(finding.recommendation)\n\n"
        }
        return text
    }
}
