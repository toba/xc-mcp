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
            "Build and launch a macOS app under LLDB debugger. This is the equivalent of Xcode's Run button — it builds incrementally, launches via Launch Services with DYLD_FRAMEWORK_PATH for non-embedded frameworks, and attaches the debugger. Use all existing debug tools (debug_stack, debug_breakpoint_add, etc.) with the returned PID.",
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
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let arch = arguments.getString("arch")
        let launchArgs = arguments.getStringArray("args")
        let stopAtEntry = arguments.getBool("stop_at_entry")

        // Extract user-provided env vars
        var userEnv: [String: String] = [:]
        if case let .object(envDict) = arguments["env"] {
            for (key, value) in envDict {
                if case let .string(v) = value {
                    userEnv[key] = v
                }
            }
        }

        do {
            // Step 1: Get build settings to find bundle ID for existing session cleanup
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            let bundleId = extractBuildSetting(
                "PRODUCT_BUNDLE_IDENTIFIER", from: buildSettings.stdout,
            )

            // Kill any existing session for this bundle ID
            if let bundleId {
                if let existing = await LLDBSessionManager.shared.getSession(bundleId: bundleId) {
                    // Kill the old process and terminate the session
                    try? await existing.session.sendCommand("process kill")
                    await LLDBSessionManager.shared.removeSession(bundleId: bundleId)
                }
            }

            // Step 2: Build (incremental — fast if nothing changed)
            var destination = "platform=macOS"
            if let arch {
                destination += ",arch=\(arch)"
            }

            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                timeout: Self.buildTimeout,
                onProgress: { line in
                    Self.logger.info("\(line)")
                },
            )

            let parsedBuild = ErrorExtractor.parseBuildOutput(buildResult.output)

            if !buildResult.succeeded, parsedBuild.status != "success" {
                let errorOutput = BuildResultFormatter.formatBuildResult(parsedBuild)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }

            // Step 3: Extract paths from build settings
            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings.",
                )
            }

            let builtProductsDir = extractBuildSetting(
                "BUILT_PRODUCTS_DIR", from: buildSettings.stdout,
            )

            // Extract executable name from the app bundle name
            let appName =
                URL(fileURLWithPath: appPath).lastPathComponent
                    .replacingOccurrences(of: ".app", with: "")

            // Step 4: Prepare the app for debug launch.
            // Sandboxed apps crash with SIGABRT when launched directly via LLDB's
            // `process launch` because the sandbox isn't initialized. We must launch
            // via /usr/bin/open (Launch Services). But apps with non-embedded frameworks
            // need DYLD_FRAMEWORK_PATH, which dyld strips for hardened-runtime apps.
            // Solution: inject LSEnvironment into Info.plist + add the
            // allow-dyld-environment-variables entitlement, then re-sign.
            try await prepareAppForDebugLaunch(
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

            // Build response
            var message = "Successfully built and launched '\(scheme)' under debugger"
            message += "\nPID: \(pid)"
            message += "\nApp path: \(appPath)"
            if let bundleId {
                message += "\nBundle ID: \(bundleId)"
            }
            if stopAtEntry {
                message += "\n\nProcess stopped at entry point. Use debug_continue to run."
            } else {
                message += "\n\nDebugger attached. Use debug tools with pid: \(pid)"
            }
            message += "\n\n" + launchResult.output

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }

    // MARK: - Build Settings Extraction

    private func extractBuildSetting(_ key: String, from buildSettings: String) -> String? {
        BuildSettingExtractor.extractSetting(key, from: buildSettings)
    }

    /// Prepares a debug app bundle for launch via `/usr/bin/open`.
    ///
    /// Framework targets with `INSTALL_PATH = /Library/Frameworks` produce binaries
    /// with absolute install names (e.g. `/Library/Frameworks/Foo.framework/...`).
    /// Xcode handles this at runtime via `DYLD_FRAMEWORK_PATH`, but that's stripped
    /// by SIP for hardened-runtime apps launched through Launch Services.
    ///
    /// This method:
    /// 1. Symlinks non-embedded frameworks from BUILT_PRODUCTS_DIR into the app bundle
    /// 2. Rewrites absolute `/Library/Frameworks/` install names to `@rpath/` in
    ///    binaries inside the bundle using `install_name_tool`
    /// 3. Re-signs the bundle to cover the modified content
    private func prepareAppForDebugLaunch(
        appPath: String, builtProductsDir: String?,
    ) async throws {
        guard let dir = builtProductsDir else { return }

        let fm = FileManager.default
        let frameworksDir = "\(appPath)/Contents/Frameworks"
        try fm.createDirectory(atPath: frameworksDir, withIntermediateDirectories: true)

        // Step 1: Symlink frameworks from BUILT_PRODUCTS_DIR into the app bundle
        let builtProductsURL = URL(fileURLWithPath: dir)
        let contents = try fm.contentsOfDirectory(
            at: builtProductsURL, includingPropertiesForKeys: nil,
        )

        var modified = false
        for item in contents where item.pathExtension == "framework" {
            let destPath = "\(frameworksDir)/\(item.lastPathComponent)"
            if fm.fileExists(atPath: destPath) { continue }
            try fm.createSymbolicLink(atPath: destPath, withDestinationPath: item.path)
            modified = true
        }
        for item in contents where item.pathExtension == "dylib" {
            let destPath = "\(frameworksDir)/\(item.lastPathComponent)"
            if fm.fileExists(atPath: destPath) { continue }
            try fm.createSymbolicLink(atPath: destPath, withDestinationPath: item.path)
            modified = true
        }

        // Step 2: Rewrite absolute /Library/Frameworks/ install names to @rpath/
        // in all Mach-O binaries inside the app bundle's MacOS directory.
        let macOSDir = "\(appPath)/Contents/MacOS"
        if let macOSContents = try? fm.contentsOfDirectory(atPath: macOSDir) {
            for file in macOSContents {
                let filePath = "\(macOSDir)/\(file)"
                modified = try await rewriteAbsoluteInstallNames(at: filePath) || modified
            }
        }

        guard modified else { return }

        // Step 3: Re-sign with the original identity
        try await resignBundle(appPath: appPath)
    }

    /// Rewrites absolute `/Library/Frameworks/` references to `@rpath/` using install_name_tool.
    ///
    /// Returns true if any changes were made.
    private func rewriteAbsoluteInstallNames(at binaryPath: String) async throws -> Bool {
        let otoolResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/otool"),
            arguments: ["-L", binaryPath],
        )
        guard otoolResult.succeeded else { return false }

        let prefix = "/Library/Frameworks/"
        var changes: [(old: String, new: String)] = []

        for line in otoolResult.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                if let parenRange = trimmed.range(of: " (compatibility") {
                    let oldPath = String(trimmed[..<parenRange.lowerBound])
                    let newPath = "@rpath/" + String(oldPath.dropFirst(prefix.count))
                    changes.append((old: oldPath, new: newPath))
                }
            }
        }

        guard !changes.isEmpty else { return false }

        var args: [String] = []
        for change in changes {
            args += ["-change", change.old, change.new]
        }
        args.append(binaryPath)

        let installResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/install_name_tool"),
            arguments: Arguments(args),
        )

        if !installResult.succeeded {
            Self.logger
                .warning("install_name_tool failed for \(binaryPath): \(installResult.stderr)")
            return false
        }

        return true
    }

    /// Re-signs the app bundle preserving the original signing identity and entitlements.
    private func resignBundle(appPath: String) async throws {
        // Extract signing identity
        let identityResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: ["-dvvv", appPath],
            mergeStderr: true,
        )

        var signingIdentity = "-"
        for line in identityResult.stdout.components(separatedBy: .newlines)
            where line.hasPrefix("Authority=")
        {
            signingIdentity = String(line.dropFirst("Authority=".count))
            break
        }

        // Extract entitlements
        let extractResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: ["-d", "--entitlements", "-", "--xml", appPath],
        )
        var tempEntitlementsURL: URL?

        if let data = extractResult.stdout.data(using: .utf8), !data.isEmpty {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("debug_entitlements_\(UUID().uuidString).plist")
            try data.write(to: url)
            tempEntitlementsURL = url
        }

        defer {
            if let url = tempEntitlementsURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Re-sign
        var signArgs = ["--force", "--sign", signingIdentity, "--deep"]
        if let url = tempEntitlementsURL {
            signArgs += ["--entitlements", url.path]
        }
        signArgs.append(appPath)

        let signResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: Arguments(signArgs),
        )

        if !signResult.succeeded {
            Self.logger.warning("Re-signing failed: \(signResult.stderr)")
        }
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
