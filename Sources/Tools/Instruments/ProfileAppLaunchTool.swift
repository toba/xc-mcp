import MCP
import XCMCPCore
import Foundation

/// One-shot app launch profiling that builds, launches with xctrace "App Launch" template,
/// and returns the trace summary.
///
/// Combines build → xctrace record (App Launch template) → export summary into a single
/// tool call to answer "why is my app slow to become responsive?"
public struct ProfileAppLaunchTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let xctraceRunner: XctraceRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        xctraceRunner: XctraceRunner = XctraceRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.xctraceRunner = xctraceRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "profile_app_launch",
            description:
            "Build a macOS app and profile its launch using Instruments 'App Launch' template. Returns trace file path and exported summary. Single tool call to diagnose slow app startup.",
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
                    "template": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Instruments template to use. Defaults to 'App Launch'. Other useful options: 'Time Profiler', 'Animation Hitches'.",
                        ),
                    ]),
                    "duration": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Recording duration in seconds after app launch. Default: 15.",
                        ),
                    ]),
                ]),
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
        let template = arguments.getString("template") ?? "App Launch"
        let duration = arguments.getInt("duration") ?? 15

        do {
            // Step 1: Build
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: "platform=macOS",
                configuration: configuration,
                environment: environment,
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

            guard let appPath = BuildSettingExtractor.extractAppPath(from: buildSettings.stdout)
            else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings.",
                )
            }

            // Prepare app bundle
            let builtProductsDir = BuildSettingExtractor.extractSetting(
                "BUILT_PRODUCTS_DIR", from: buildSettings.stdout,
            )
            try await AppBundlePreparer.prepare(
                appPath: appPath, builtProductsDir: builtProductsDir,
            )

            // Step 3: Record with xctrace using the app launch template
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let tracePath = "/tmp/launch_profile_\(timestamp).trace"

            let process = try xctraceRunner.record(
                template: template,
                outputPath: tracePath,
                device: nil,
                timeLimit: "\(duration)s",
                attachPID: nil,
                attachName: nil,
                allProcesses: false,
                launchPath: appPath,
            )

            // Wait for xctrace to finish (it auto-stops after time_limit)
            // Use continuation to avoid blocking the cooperative thread pool.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
            }

            var message = "Profile complete for '\(scheme)' with template '\(template)'\n"
            message += "Trace file: \(tracePath)\n"
            message += "Duration: \(duration)s\n\n"

            // Step 4: Export table of contents
            let tocResult = try await xctraceRunner.export(
                inputPath: tracePath,
                xpath: nil,
                toc: true,
            )

            if tocResult.succeeded, !tocResult.stdout.isEmpty {
                message += "--- Trace Table of Contents ---\n"
                message += tocResult.stdout
            } else {
                message +=
                    "Note: Could not export trace summary. Open \(tracePath) in Instruments.app for full analysis."
                if !tocResult.stderr.isEmpty {
                    message += "\nxctrace export stderr: \(tocResult.stderr)"
                }
            }

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw error.asMCPError()
        }
    }
}
