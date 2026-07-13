import MCP
import XCMCPCore
import Foundation
import Subprocess

/// Builds an .xcarchive for macOS or iOS using `xcodebuild archive`.
///
/// Archive is structurally distinct from `build_macos`/`build_sim`:
///
/// - Archive forces `ARCHS_STANDARD` regardless of host (iOS = arm64; macOS = arm64+x86_64).
/// - Archive triggers the Install action, which is when `MERGEABLE_LIBRARY` merging happens, the
///   codesign + dSYM extraction, and the embedded-frameworks copy phase.
/// - Archive resolves the explicit-module-build dependency graph against
///   `ArchiveIntermediates/<scheme>/...` instead of `Build/Intermediates.noindex/...`, so
///   structural archive bugs (mergeable-library duplicate symbols, cross-platform module
///   leakage) only reproduce here.
public struct ArchiveTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(), sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "archive",
            description:
                "Build an .xcarchive for macOS or iOS via `xcodebuild archive`. Reproduces "
                + "Xcode Cloud / Organizer archive behavior locally — runs the Install action, "
                + "merges mergeable libraries, extracts dSYMs, and resolves explicit-module "
                + "dependencies against ArchiveIntermediates/. Use this to reproduce archive-only "
                + "failures that `build_macos` and `build_sim` miss.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(
                    [
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
                                "The scheme to archive. Uses session default if not specified.",
                            ),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration. Defaults to Release (matches Xcode Cloud).",
                            ),
                        ]),
                        "platform": .object([
                            "type": .string("string"),
                            "enum": .array([.string("macOS"), .string("iOS")]),
                            "description": .string(
                                "Target platform. Sets destination to 'generic/platform=macOS' "
                                + "or 'generic/platform=iOS'. Defaults to 'macOS'.",
                            ),
                        ]),
                        "archive_path": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Path where the .xcarchive bundle will be written. Required.",
                            ),
                        ]),
                        "code_signing_allowed": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When false (default), passes CODE_SIGNING_ALLOWED=NO and "
                                + "CODE_SIGNING_REQUIRED=NO so the archive runs without provisioning "
                                + "profiles — matches the XCC pre-archive flags used for CI repro. "
                                + "Set to true when you need a real signed archive for export.",
                            ),
                        ]),
                        "skip_macro_validation": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When true, passes -skipMacroValidation. Mirrors XCC pre-archive flags.",
                            ),
                        ]),
                        "skip_package_plugin_validation": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When true, passes -skipPackagePluginValidation. Mirrors XCC "
                                + "pre-archive flags.",
                            ),
                        ]),
                        "errors_only": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When true, only show compiler errors, linker errors, and the "
                                + "build summary — all warnings are suppressed.",
                            ),
                        ]),
                        "show_warnings": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When true, include detailed compiler warnings in the output.",
                            ),
                        ]),
                        "timeout": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Maximum time in seconds for the archive. Defaults to 600 "
                                + "(10 minutes — archives are slower than builds due to the "
                                + "Install action, dSYM extraction, and mergeable-library link).",
                            ),
                        ]),
                    ].merging([String: Value].continueBuildingSchemaProperty) { _, new in new }
                        .merging([String: Value].enableSanitizersSchemaProperty) { _, new in new }
                        .merging([String: Value].buildSettingsSchemaProperty) { _, new in new }
                        .merging([String: Value].extraArgsSchemaProperty) { _, new in new },
                ),
                "required": .array([.string("archive_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let extraArgs = await sessionManager.resolveExtraArgs(from: arguments)
        let configuration = arguments.getString("configuration") ?? "Release"
        let platform = arguments.getString("platform") ?? "macOS"
        guard let archivePath = arguments.getString("archive_path") else {
            throw MCPError.invalidParams("archive_path is required")
        }
        let codeSigningAllowed = arguments.getBool("code_signing_allowed")
        let skipMacroValidation = arguments.getBool("skip_macro_validation")
        let skipPackagePluginValidation = arguments.getBool("skip_package_plugin_validation")
        let errorsOnly = arguments.getBool("errors_only")
        let showWarnings = arguments.getBool("show_warnings")
        let timeout =
            arguments.getInt("timeout").map { TimeInterval($0) } ?? 600

        guard platform == "macOS" || platform == "iOS" else {
            throw MCPError.invalidParams(
                "platform must be 'macOS' or 'iOS' (got '\(platform)')",
            )
        }

        let projectRoot = ErrorExtractor.projectRoot(
            projectPath: projectPath, workspacePath: workspacePath,
        )

        do {
            if platform == "macOS" {
                try await BuildSettingExtractor.validateMacOSSupport(
                    runner: xcodebuildRunner,
                    projectPath: projectPath,
                    workspacePath: workspacePath,
                    scheme: scheme,
                    configuration: configuration,
                )
            }

            let destination = "generic/platform=\(platform)"

            var extra: [String] = ["-archivePath", archivePath]
            if skipMacroValidation { extra.append("-skipMacroValidation") }
            if skipPackagePluginValidation { extra.append("-skipPackagePluginValidation") }
            if !codeSigningAllowed {
                extra += [
                    "CODE_SIGNING_ALLOWED=NO",
                    "CODE_SIGNING_REQUIRED=NO",
                    "CODE_SIGN_IDENTITY=",
                    "CODE_SIGN_ENTITLEMENTS=",
                ]
            }

            let hasExplicitTimeout = arguments["timeout"] != nil
            let result = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                action: "archive",
                additionalArguments: extra
                    + arguments.continueBuildingArgs()
                    + arguments.enableSanitizersArgs()
                    + arguments.buildSettingOverrides()
                    + extraArgs,
                environment: environment,
                timeout: timeout,
                outputTimeout: hasExplicitTimeout ? nil : XcodebuildRunner.outputTimeout,
            )

            try ErrorExtractor.checkBuildSuccess(
                result, projectRoot: projectRoot, errorsOnly: errorsOnly,
            )

            // Defense in depth: xcodebuild can report success without writing the .xcarchive
            // bundle — for example when the output-stuck watchdog short-circuits during the
            // install/codesign phase after the build phase printed a terminal marker. Verify
            // the bundle actually exists so callers don't get a misleading "succeeded" message
            // and then fail to find the archive on disk. (y04-t3c)
            if !FileManager.default.fileExists(atPath: archivePath) {
                throw MCPError.internalError(
                    "xcodebuild reported archive success for scheme '\(scheme)' (\(platform)), "
                    + "but no .xcarchive bundle was created at \(archivePath). "
                    + "The build phase likely completed while the install/codesign phase was "
                    + "still running. Retry with a larger `timeout`, or inspect the build log "
                    + "via show_build_log.",
                )
            }

            let summary = ErrorExtractor.extractBuildErrors(
                from: result.output, projectRoot: projectRoot, errorsOnly: errorsOnly,
                showWarnings: showWarnings,
            )
            var text =
                "Archive succeeded for scheme '\(scheme)' (\(platform)) at \(archivePath)"
            if !summary.isEmpty, summary != "Build succeeded" {
                text += "\n\n" + summary
            }
            return CallTool.Result(
                content: [.text(text: text, annotations: nil, _meta: nil)],
            )
        } catch let error as XcodebuildError {
            return error.formatPartialDiagnostics(
                projectRoot: projectRoot, errorsOnly: errorsOnly, showWarnings: showWarnings,
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
