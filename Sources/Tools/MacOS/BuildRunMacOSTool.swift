import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct BuildRunMacOSTool: Sendable {
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
            name: "build_run_macos",
            description:
            "Build and run an Xcode project or workspace on macOS. This combines build_macos and launch_mac_app into a single operation.",
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
                                "The scheme to build. Uses session default if not specified.",
                            ),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug.",
                            ),
                        ]),
                        "arch": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Architecture to build for (arm64 or x86_64). Defaults to the current machine's architecture.",
                            ),
                        ]),
                        "args": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Optional arguments to pass to the app."),
                        ]),
                        "timeout": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Maximum time in seconds for the build step. Defaults to 300 (5 minutes). "
                                    + "When the build times out, partial diagnostics (errors and warnings "
                                    + "collected so far) are returned instead of an empty error.",
                            ),
                        ]),
                    ].merging([String: Value].continueBuildingSchemaProperty) { _, new in new }
                        .merging([String: Value].enableSanitizersSchemaProperty) { _, new in new }
                        .merging([String: Value].buildSettingsSchemaProperty) { _, new in new },
                ),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let arch = arguments.getString("arch")
        let launchArgs = arguments.getStringArray("args")
        let timeout =
            arguments.getInt("timeout").map { TimeInterval($0) }
                ?? XcodebuildRunner.defaultTimeout

        let projectRoot = ErrorExtractor.projectRoot(
            projectPath: projectPath, workspacePath: workspacePath,
        )

        do {
            try await BuildSettingExtractor.validateMacOSSupport(
                runner: xcodebuildRunner,
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            var destination = "platform=macOS"
            if let arch {
                destination += ",arch=\(arch)"
            }

            // Step 1: Build
            let hasExplicitTimeout = arguments["timeout"] != nil
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                additionalArguments: arguments.continueBuildingArgs()
                    + arguments
                    .enableSanitizersArgs() + arguments.buildSettingOverrides(),
                environment: environment,
                timeout: timeout,
                outputTimeout: hasExplicitTimeout ? nil : XcodebuildRunner.outputTimeout,
            )

            let parsedBuild = ErrorExtractor.parseBuildOutput(buildResult.output)

            if !buildResult.succeeded, parsedBuild.status != "success" {
                let errorOutput = BuildResultFormatter.formatBuildResult(parsedBuild)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }

            // Step 2: Get app path from build settings
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings.",
                )
            }

            // Step 3: Prepare app bundle for launch (symlink non-embedded frameworks)
            let builtProductsDir = BuildSettingExtractor.extractSetting(
                "BUILT_PRODUCTS_DIR", from: buildSettings.stdout,
            )
            try await AppBundlePreparer.prepare(
                appPath: appPath, builtProductsDir: builtProductsDir,
            )

            // Step 4: Launch app using open command
            var openArgs = [appPath]
            if !launchArgs.isEmpty {
                openArgs.append("--args")
                openArgs.append(contentsOf: launchArgs)
            }

            let result = try await ProcessResult.run("/usr/bin/open", arguments: openArgs)

            if result.succeeded {
                var message = "Successfully built and launched '\(scheme)' on macOS"
                message += "\nApp path: \(appPath)"

                // Resolve PID and check liveness
                let appName = URL(fileURLWithPath: appPath).deletingPathExtension()
                    .lastPathComponent
                let bundleId = extractBundleId(from: buildSettings.stdout)
                if let pid = await PIDResolver.findLaunchedPID(
                    bundleId: bundleId,
                    appName: appName,
                ) {
                    try await Task.sleep(for: .seconds(1))
                    if kill(pid, 0) == 0 {
                        message += "\nPID: \(pid)"
                    } else {
                        message += "\nPID: \(pid) (exited — app may have crashed on launch)"

                        CrashReportParser.appendCrashReports(
                            to: &message, processName: appName, bundleID: bundleId,
                        )
                    }
                }

                return CallTool.Result(content: [.text(
                    text: message,
                    annotations: nil,
                    _meta: nil,
                )])
            } else {
                throw MCPError.internalError("Failed to launch app: \(result.stdout)")
            }
        } catch let error as XcodebuildError {
            return error.formatPartialDiagnostics(projectRoot: projectRoot)
        } catch {
            throw try error.asMCPError()
        }
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        BuildSettingExtractor.extractAppPath(from: buildSettings)
    }

    private func extractBundleId(from buildSettings: String) -> String? {
        BuildSettingExtractor.extractBundleId(from: buildSettings)
    }
}
