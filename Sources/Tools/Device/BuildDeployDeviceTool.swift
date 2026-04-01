import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct BuildDeployDeviceTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "build_deploy_device",
            description:
            "Build, install, and launch an app on a connected device in one step. Builds for the device platform, stops any running instance, installs the .app, and launches it.",
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
                        "device": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Device UDID. Uses session default if not specified.",
                            ),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug.",
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

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let device = try await sessionManager.resolveDevice(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)

        var steps: [String] = []

        do {
            // Step 1: Look up device platform for generic destination
            let connectedDevice = try await deviceCtlRunner.lookupDevice(udid: device)
            let destination = "generic/platform=\(connectedDevice.platform)"

            // Step 2: Build
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                additionalArguments: arguments.continueBuildingArgs()
                    + arguments
                    .buildSettingOverrides(),
                environment: environment,
                outputTimeout: XcodebuildRunner.deviceOutputTimeout,
            )
            try ErrorExtractor.checkBuildSuccess(buildResult, projectRoot: nil)
            steps.append("✓ Build succeeded")

            // Step 3: Extract app path and bundle ID from build settings
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                destination: destination,
            )

            guard
                let appPath = BuildSettingExtractor.extractAppPath(
                    from: buildSettings.stdout,
                )
            else {
                throw MCPError.internalError(
                    "Build succeeded but could not determine .app path from build settings.",
                )
            }

            guard
                let bundleId = BuildSettingExtractor.extractBundleId(
                    from: buildSettings.stdout,
                )
            else {
                throw MCPError.internalError(
                    "Build succeeded but could not determine bundle identifier from build settings.",
                )
            }

            // Step 4: Stop any running instance (ignore not-running errors)
            do {
                _ = try await deviceCtlRunner.terminate(udid: device, bundleId: bundleId)
                steps.append("✓ Stopped running instance of '\(bundleId)'")
            } catch {
                switch error {
                    case .processNotFound:
                        steps.append("– No running instance of '\(bundleId)' to stop")
                    default:
                        steps.append("⚠ Could not stop app: \(error.localizedDescription)")
                }
            }

            // Step 5: Install
            let installResult = try await deviceCtlRunner.install(
                udid: device, appPath: appPath,
            )
            guard installResult.succeeded else {
                throw MCPError.internalError(
                    "Install failed: \(installResult.errorOutput)",
                )
            }
            steps.append("✓ Installed '\(appPath)'")

            // Step 6: Launch
            let launchResult = try await deviceCtlRunner.launch(
                udid: device, bundleId: bundleId,
            )
            guard launchResult.succeeded else {
                throw MCPError.internalError(
                    "Launch failed: \(launchResult.errorOutput)",
                )
            }
            steps.append("✓ Launched '\(bundleId)'")

            let summary = steps.joined(separator: "\n")
            return CallTool.Result(
                content: [
                    .text(
                        "Build and deploy succeeded for scheme '\(scheme)' on device '\(device)'\n\n\(summary)",
                    ),
                ],
            )
        } catch {
            let progress = steps.isEmpty ? "" : "\n\nProgress:\n\(steps.joined(separator: "\n"))"
            throw MCPError.internalError(
                "Build and deploy failed: \(error.localizedDescription)\(progress)",
            )
        }
    }
}
