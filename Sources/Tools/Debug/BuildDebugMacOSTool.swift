import MCP
import Logging
import XCMCPCore
import Foundation
import Subprocess

public struct BuildDebugMacOSTool: Sendable {
    /// Build timeout for debug builds (10 minutes to accommodate large projects)
    private static let buildTimeout: TimeInterval = 600

    private static let logger = Logger(label: "build_debug_macos")

    private let xcodebuildRunner: XcodebuildRunner
    private let lldbRunner: LLDBRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        lldbRunner: LLDBRunner = LLDBRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.lldbRunner = lldbRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "build_debug_macos",
            description:
            "Build and launch a macOS app under LLDB debugger. This is the equivalent of Xcode's Run button — it builds incrementally, launches via Launch Services with DYLD_FRAMEWORK_PATH for non-embedded frameworks, and attaches the debugger. Use all existing debug tools (debug_stack, debug_breakpoint_add, etc.) with the returned PID. NOTE: by default builds use a scoped DerivedData path (~/Library/Caches/xc-mcp/DerivedData) isolated from Xcode's, so the first build after building only in Xcode is fully cold (minutes on large projects). For single-agent workflows where you just built in Xcode, set XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1 to reuse Xcode's warm cache. To relaunch the same already-built binary with different env/args without rebuilding, pass skip_build: true.",
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
                        "env": .object([
                            "type": .string("object"),
                            "additionalProperties": .object(["type": .string("string")]),
                            "description": .string(
                                "Additional environment variables to set (key-value pairs).",
                            ),
                        ]),
                        "stop_at_entry": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "Stop at the entry point before running. Defaults to false.",
                            ),
                        ]),
                        "skip_build": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "Skip the build step and relaunch the already-built product under LLDB. Use to quickly relaunch the same binary with different env/args (no source changes) without paying for a build. Fails if the product hasn't been built yet. Defaults to false.",
                            ),
                        ]),
                    ].merging([String: Value].continueBuildingSchemaProperty) { _, new in new }
                        .merging([String: Value].buildSettingsSchemaProperty) { _, new in new },
                ),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(
        arguments: [String: Value],
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let arch = arguments.getString("arch")
        let launchArgs = arguments.getStringArray("args")
        let stopAtEntry = arguments.getBool("stop_at_entry")
        let skipBuild = arguments.getBool("skip_build")

        // Merge session env with per-invocation env (per-invocation wins)
        let resolvedEnv = await sessionManager.resolveEnvironment(from: arguments)
        // Also build a plain dict for LLDBRunner which takes [String: String]
        var userEnv: [String: String] = [:]
        if let sessionEnv = await sessionManager.env {
            userEnv.merge(sessionEnv) { _, new in new }
        }
        if case let .object(envDict) = arguments["env"] {
            for (key, value) in envDict {
                if case let .string(v) = value {
                    userEnv[key] = v
                }
            }
        }

        // Resolve the build destination up front so it can also narrow the
        // pre-build `-showBuildSettings` pass below.
        var destination = "platform=macOS"
        if let arch {
            destination += ",arch=\(arch)"
        }

        do {
            // Step 1: Get build settings to find bundle ID for existing session cleanup.
            // Pass the concrete macOS destination so xcodebuild resolves only this
            // platform's settings instead of the entire SPM package graph for every
            // target — without it this pre-pass alone can take tens of seconds on
            // projects with package dependencies, before compilation even starts.
            var buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                destination: destination,
            )

            // An iOS-only scheme can't resolve `-destination platform=macOS`, so the
            // fast pass above returns no settings. Retry without a destination to recover
            // the full settings dump — this is what lets the SUPPORTED_PLATFORMS check
            // below emit a friendly "scheme does not support macOS" error instead of an
            // opaque destination-resolution failure later in the build.
            if BuildSettingExtractor.extractSetting(
                "PRODUCT_BUNDLE_IDENTIFIER", from: buildSettings.stdout,
            ) == nil,
                BuildSettingExtractor.extractSetting(
                    "SUPPORTED_PLATFORMS", from: buildSettings.stdout,
                ) == nil
            {
                buildSettings = try await xcodebuildRunner.showBuildSettings(
                    projectPath: projectPath,
                    workspacePath: workspacePath,
                    scheme: scheme,
                    configuration: configuration,
                )
            }

            // Validate that this scheme supports macOS before building
            if let platforms = BuildSettingExtractor.extractSetting(
                "SUPPORTED_PLATFORMS", from: buildSettings.stdout,
            ) {
                let platformList = platforms.split(separator: " ").map(String.init)
                if !platformList.contains("macosx") {
                    let platformDesc = platformList.joined(separator: ", ")
                    throw MCPError.invalidRequest(
                        "Scheme '\(scheme)' does not support macOS (supported platforms: \(platformDesc)). "
                            + "Use the xc-simulator server's build/test tools for iOS projects, "
                            + "or add Mac Catalyst support in the Xcode project.",
                    )
                }
            }

            let bundleId = extractBuildSetting(
                "PRODUCT_BUNDLE_IDENTIFIER", from: buildSettings.stdout,
            )

            // Kill any existing session for this bundle ID
            if let bundleId {
                if let existing = await LLDBSessionManager.shared.getSession(bundleId: bundleId) {
                    // Kill the old process and terminate the session
                    _ = try? await existing.session.sendCommand("process kill")
                    await LLDBSessionManager.shared.removeSession(bundleId: bundleId)
                }
            }

            // Step 2: Build (incremental — fast if nothing changed). Skipped when the
            // caller only wants to relaunch the already-built product with new env/args.
            if skipBuild {
                onProgress?("Skipping build (skip_build); relaunching existing product")
            } else {
                let buildResult = try await xcodebuildRunner.build(
                    projectPath: projectPath,
                    workspacePath: workspacePath,
                    scheme: scheme,
                    destination: destination,
                    configuration: configuration,
                    additionalArguments: arguments.continueBuildingArgs()
                        + arguments
                        .buildSettingOverrides(),
                    environment: resolvedEnv,
                    timeout: Self.buildTimeout,
                    onProgress: { line in
                        Self.logger.info("\(line)")
                        onProgress?(line)
                    },
                )

                let parsedBuild = ErrorExtractor.parseBuildOutput(buildResult.output)

                if !buildResult.succeeded, parsedBuild.status != "success" {
                    let errorOutput = BuildResultFormatter.formatBuildResult(parsedBuild)
                    throw MCPError.internalError("Build failed:\n\(errorOutput)")
                }
            }

            // Step 3: Extract paths from build settings
            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings.",
                )
            }

            // With skip_build, the product must already exist on disk — there's no build
            // step to produce it. Fail loudly rather than handing /usr/bin/open a missing
            // bundle (which would surface as an opaque launch failure).
            if skipBuild, !FileManager.default.fileExists(atPath: appPath) {
                throw MCPError.invalidRequest(
                    "skip_build was set but no built product exists at \(appPath). "
                        + "Run build_debug_macos without skip_build first to produce it.",
                )
            }

            let builtProductsDir = extractBuildSetting(
                "BUILT_PRODUCTS_DIR", from: buildSettings.stdout,
            )

            // Resolve the actual executable name for LLDB's --waitfor.
            // The .app folder name may differ from the binary (e.g. "App (debug).app"
            // contains a binary named "App"). Prefer EXECUTABLE_NAME from build settings,
            // then CFBundleExecutable from Info.plist, then fall back to the folder name.
            let appName: String = {
                if let name = extractBuildSetting("EXECUTABLE_NAME", from: buildSettings.stdout) {
                    return name
                }
                let infoPlistPath = "\(appPath)/Contents/Info.plist"
                if let data = FileManager.default.contents(atPath: infoPlistPath),
                   let plist = try? PropertyListSerialization.propertyList(
                       from: data, format: nil,
                   ) as? [String: Any],
                   let name = plist["CFBundleExecutable"] as? String
                {
                    return name
                }
                return URL(fileURLWithPath: appPath).lastPathComponent
                    .replacingOccurrences(of: ".app", with: "")
            }()

            // Step 4: Prepare the app for debug launch.
            // Sandboxed apps crash with SIGABRT when launched directly via LLDB's
            // `process launch` because the sandbox isn't initialized. We must launch
            // via /usr/bin/open (Launch Services). But apps with non-embedded frameworks
            // need DYLD_FRAMEWORK_PATH, which dyld strips for hardened-runtime apps.
            // Solution: symlink frameworks into bundle + rewrite install names + re-sign.
            try await AppBundlePreparer.prepare(
                appPath: appPath, builtProductsDir: builtProductsDir,
            )

            // Step 5: Launch via /usr/bin/open + LLDB --waitfor attach
            let (launchResult, pid) = try await lldbRunner.launchViaOpenAndAttach(
                appPath: appPath,
                executableName: appName,
                arguments: launchArgs,
                environment: userEnv,
                stopAtEntry: stopAtEntry,
            )

            // Step 7: Register bundle ID mapping
            if let bundleId, pid > 0 {
                await LLDBSessionManager.shared.registerBundleId(bundleId, forPID: pid)
            }

            // Detect early crash from the launch output
            let crashed = launchResult.output
                .contains("Process crashed immediately after launch")

            // Build response
            var message: String
            if crashed {
                message = "Built '\(scheme)' but process crashed immediately after launch"
                message += "\nPID: \(pid)"
                if let bundleId {
                    message += "\nBundle ID: \(bundleId)"
                }
                message +=
                    "\n\nDebugger attached. Use debug_stack, debug_variables, debug_lldb_command for investigation."
                message += "\n\n" + launchResult.output

                // A dyld abort (the `__abort_with_payload` SIGABRT) shows only a generic backtrace
                // here — the real reason (e.g. "Library not loaded … different Team IDs") lives in
                // the crash report. Surface it, plus a Team-ID consistency check, so the actionable
                // cause is in the launch output instead of requiring a manual DiagnosticReports grep.
                if let mismatch = await CodeSignInspector.checkBundleConsistency(appPath: appPath),
                   let warning = mismatch.warning()
                {
                    message += "\n\n" + warning
                }
                CrashReportParser.appendCrashReports(
                    to: &message,
                    processName: appName,
                    bundleID: bundleId,
                )
            } else {
                let verb = skipBuild ? "relaunched" : "built and launched"
                message = "Successfully \(verb) '\(scheme)' under debugger"
                message += "\nPID: \(pid)"
                message += "\nApp path: \(appPath)"
                if let bundleId {
                    message += "\nBundle ID: \(bundleId)"
                }
                if stopAtEntry {
                    message +=
                        "\n\nProcess stopped at entry point. Use debug_continue to run."
                } else {
                    message += "\n\nDebugger attached. Use debug tools with pid: \(pid)"
                }
                message += "\n\n" + launchResult.output
            }

            return CallTool.Result(
                content: [.text(text: message, annotations: nil, _meta: nil)],
                isError: crashed,
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    // MARK: - Build Settings Extraction

    private func extractBuildSetting(_ key: String, from buildSettings: String) -> String? {
        BuildSettingExtractor.extractSetting(key, from: buildSettings)
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        // Try CODESIGNING_FOLDER_PATH first
        if let path = extractBuildSetting("CODESIGNING_FOLDER_PATH", from: buildSettings),
           path.hasSuffix(".app")
        {
            return path
        }

        // Fallback: TARGET_BUILD_DIR + FULL_PRODUCT_NAME
        if let dir = extractBuildSetting("TARGET_BUILD_DIR", from: buildSettings),
           let name = extractBuildSetting("FULL_PRODUCT_NAME", from: buildSettings)
        {
            return "\(dir)/\(name)"
        }

        return nil
    }
}
