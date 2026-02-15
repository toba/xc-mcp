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
                "Build and launch a macOS app under LLDB debugger. This is the equivalent of Xcode's Run button — it builds incrementally, sets DYLD_FRAMEWORK_PATH/DYLD_LIBRARY_PATH so frameworks load correctly, and launches with the debugger attached from the start. Use all existing debug tools (debug_stack, debug_breakpoint_add, etc.) with the returned PID.",
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

            let executablePath = extractExecutablePath(from: buildSettings.stdout, appPath: appPath)
            guard let executablePath else {
                throw MCPError.internalError(
                    "Could not determine executable path from build settings.")
            }

            let builtProductsDir = extractBuildSetting(
                "BUILT_PRODUCTS_DIR", from: buildSettings.stdout)

            // Step 4: Build environment with DYLD paths
            var environment: [String: String] = [:]
            if let dir = builtProductsDir {
                environment["DYLD_FRAMEWORK_PATH"] = dir
                environment["DYLD_LIBRARY_PATH"] = dir
            }
            // Merge user-provided env vars (user wins on conflict)
            for (key, value) in userEnv {
                environment[key] = value
            }

            // Step 5: Launch under LLDB
            let (launchResult, pid) = try await lldbRunner.launchProcess(
                executablePath: executablePath,
                environment: environment,
                arguments: launchArgs,
                stopAtEntry: stopAtEntry
            )

            // Step 6: Register bundle ID mapping
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
        let lines = buildSettings.components(separatedBy: .newlines)
        for line in lines where line.contains(key) {
            if let equalsRange = line.range(of: " = ") {
                return String(line[equalsRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        let lines = buildSettings.components(separatedBy: .newlines)

        // First try CODESIGNING_FOLDER_PATH
        for line in lines where line.contains("CODESIGNING_FOLDER_PATH") {
            if let range = line.range(of: "/") {
                let path = String(line[range.lowerBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ",", with: "")
                if path.hasSuffix(".app") {
                    return path
                }
            }
        }

        // Fallback: TARGET_BUILD_DIR + FULL_PRODUCT_NAME
        var targetBuildDir: String?
        var fullProductName: String?

        for line in lines {
            if line.contains("TARGET_BUILD_DIR") && !line.contains("EFFECTIVE") {
                if let equalsRange = line.range(of: " = ") {
                    targetBuildDir = String(line[equalsRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            if line.contains("FULL_PRODUCT_NAME") {
                if let equalsRange = line.range(of: " = ") {
                    fullProductName = String(line[equalsRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        if let dir = targetBuildDir, let name = fullProductName {
            return "\(dir)/\(name)"
        }

        return nil
    }

    private func extractExecutablePath(from buildSettings: String, appPath: String) -> String? {
        // Try EXECUTABLE_PATH from build settings
        if let execPath = extractBuildSetting("EXECUTABLE_PATH", from: buildSettings) {
            // EXECUTABLE_PATH is relative to TARGET_BUILD_DIR, but we can construct
            // the full path from the app path
            if let builtProductsDir = extractBuildSetting("BUILT_PRODUCTS_DIR", from: buildSettings)
            {
                return "\(builtProductsDir)/\(execPath)"
            }
        }

        // Fallback: derive from app bundle
        // For MyApp.app, the executable is typically at MyApp.app/Contents/MacOS/MyApp
        let appName = URL(fileURLWithPath: appPath).lastPathComponent
            .replacingOccurrences(of: ".app", with: "")
        return "\(appPath)/Contents/MacOS/\(appName)"
    }
}
