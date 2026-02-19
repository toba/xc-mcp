import Foundation
import MCP
import XCMCPCore

public struct BuildRunMacOSTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager
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

        do {
            var destination = "platform=macOS"
            if let arch {
                destination += ",arch=\(arch)"
            }

            // Step 1: Build
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration
            )

            if !buildResult.succeeded {
                let errorOutput = ErrorExtractor.extractBuildErrors(from: buildResult.output)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }

            // Step 2: Get app path from build settings
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration
            )

            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings.")
            }

            // Step 3: Launch app using open command
            var openArgs = [appPath]
            if !launchArgs.isEmpty {
                openArgs.append("--args")
                openArgs.append(contentsOf: launchArgs)
            }

            let result = try ProcessResult.run("/usr/bin/open", arguments: openArgs)

            if result.succeeded {
                var message = "Successfully built and launched '\(scheme)' on macOS"
                message += "\nApp path: \(appPath)"
                return CallTool.Result(content: [.text(message)])
            } else {
                throw MCPError.internalError("Failed to launch app: \(result.stdout)")
            }
        } catch {
            throw error.asMCPError()
        }
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        BuildSettingExtractor.extractAppPath(from: buildSettings)
    }
}
