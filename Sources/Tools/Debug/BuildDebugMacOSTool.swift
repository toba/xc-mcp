import Foundation
import Logging
import MCP
import XCMCPCore

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
        sessionManager: SessionManager
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
                            "Path to the .xcodeproj file. Uses session default if not specified."),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified."
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to build. Uses session default if not specified."),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                    "arch": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Architecture to build for (arm64 or x86_64). Defaults to the current machine's architecture."
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
                            "Additional environment variables to set (key-value pairs)."),
                    ]),
                    "stop_at_entry": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Stop at the entry point before running. Defaults to false."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments)
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
                configuration: configuration
            )

            let bundleId = extractBuildSetting(
                "PRODUCT_BUNDLE_IDENTIFIER", from: buildSettings.stdout)

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
                }
            )

            if !buildResult.succeeded {
                let errorOutput = ErrorExtractor.extractBuildErrors(from: buildResult.output)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }

            // Step 3: Extract paths from build settings
            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings.")
            }

            let builtProductsDir = extractBuildSetting(
                "BUILT_PRODUCTS_DIR", from: buildSettings.stdout)

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
            try prepareAppForDebugLaunch(
                appPath: appPath, builtProductsDir: builtProductsDir)

            // Step 5: Launch via /usr/bin/open + LLDB --waitfor attach
            let (launchResult, pid) = try await lldbRunner.launchViaOpenAndAttach(
                appPath: appPath,
                executableName: appName,
                arguments: launchArgs,
                environment: userEnv,
                stopAtEntry: stopAtEntry
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
        appPath: String, builtProductsDir: String?
    ) throws {
        guard let dir = builtProductsDir else { return }

        let fm = FileManager.default
        let frameworksDir = "\(appPath)/Contents/Frameworks"
        try fm.createDirectory(atPath: frameworksDir, withIntermediateDirectories: true)

        // Step 1: Symlink frameworks from BUILT_PRODUCTS_DIR into the app bundle
        let builtProductsURL = URL(fileURLWithPath: dir)
        let contents = try fm.contentsOfDirectory(
            at: builtProductsURL, includingPropertiesForKeys: nil)

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
                modified = try rewriteAbsoluteInstallNames(at: filePath) || modified
            }
        }

        guard modified else { return }

        // Step 3: Re-sign with the original identity
        try resignBundle(appPath: appPath)
    }

    /// Rewrites absolute `/Library/Frameworks/` references to `@rpath/` using install_name_tool.
    ///
    /// Returns true if any changes were made.
    private func rewriteAbsoluteInstallNames(at binaryPath: String) throws -> Bool {
        let otoolProc = Process()
        otoolProc.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        otoolProc.arguments = ["-L", binaryPath]
        let otoolOut = Pipe()
        otoolProc.standardOutput = otoolOut
        otoolProc.standardError = Pipe()
        try otoolProc.run()
        otoolProc.waitUntilExit()

        guard otoolProc.terminationStatus == 0 else { return false }

        let output =
            String(
                data: otoolOut.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? ""

        let prefix = "/Library/Frameworks/"
        var changes: [(old: String, new: String)] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                // Extract the path (before the " (compatibility" part)
                if let parenRange = trimmed.range(of: " (compatibility") {
                    let oldPath = String(trimmed[..<parenRange.lowerBound])
                    // /Library/Frameworks/Foo.framework/... → @rpath/Foo.framework/...
                    let newPath = "@rpath/" + String(oldPath.dropFirst(prefix.count))
                    changes.append((old: oldPath, new: newPath))
                }
            }
        }

        guard !changes.isEmpty else { return false }

        // Apply all changes in a single install_name_tool invocation
        var args: [String] = []
        for change in changes {
            args += ["-change", change.old, change.new]
        }
        args.append(binaryPath)

        let installNameProc = Process()
        installNameProc.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
        installNameProc.arguments = args
        let installErr = Pipe()
        installNameProc.standardError = installErr
        try installNameProc.run()
        installNameProc.waitUntilExit()

        if installNameProc.terminationStatus != 0 {
            let errStr =
                String(
                    data: installErr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? ""
            Self.logger.warning("install_name_tool failed for \(binaryPath): \(errStr)")
            return false
        }

        return true
    }

    /// Re-signs the app bundle preserving the original signing identity and entitlements.
    private func resignBundle(appPath: String) throws {
        // Extract signing identity
        let identityProc = Process()
        identityProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        identityProc.arguments = ["-dvvv", appPath]
        let identityOut = Pipe()
        identityProc.standardOutput = identityOut
        identityProc.standardError = identityOut
        try identityProc.run()
        identityProc.waitUntilExit()

        let identityStr =
            String(
                data: identityOut.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? ""

        var signingIdentity = "-"
        for line in identityStr.components(separatedBy: .newlines)
        where line.hasPrefix("Authority=") {
            signingIdentity = String(line.dropFirst("Authority=".count))
            break
        }

        // Extract entitlements
        let extractProc = Process()
        extractProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        extractProc.arguments = ["-d", "--entitlements", "-", "--xml", appPath]
        let extractOut = Pipe()
        extractProc.standardOutput = extractOut
        extractProc.standardError = Pipe()
        try extractProc.run()
        extractProc.waitUntilExit()

        let entitlementsData = extractOut.fileHandleForReading.readDataToEndOfFile()
        var tempEntitlementsURL: URL?

        if !entitlementsData.isEmpty {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("debug_entitlements_\(UUID().uuidString).plist")
            try entitlementsData.write(to: url)
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

        let signProc = Process()
        signProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProc.arguments = signArgs
        let signErr = Pipe()
        signProc.standardError = signErr
        try signProc.run()
        signProc.waitUntilExit()

        if signProc.terminationStatus != 0 {
            let errData = signErr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            Self.logger.warning("Re-signing failed: \(errStr)")
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
