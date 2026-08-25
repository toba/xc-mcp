import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct BuildDeployDeviceTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        deviceCtlRunner: DeviceCtlRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
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
                        .merging([String: Value].buildSettingsSchemaProperty) { _, new in new }
                        .merging([String: Value].extraArgsSchemaProperty) { _, new in new }
                        .merging([String: Value].timeoutSchemaProperty(defaultSeconds: 300)) {
                            _, new in new
                        }
                        .merging([String: Value].outputTimeoutSchemaProperty(defaultSeconds: 120)) {
                            _, new in new
                        },
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
        let extraArgs = await sessionManager.resolveExtraArgs(from: arguments)
        let timeout = arguments.resolveTimeout(default: XcodebuildRunner.defaultTimeout)
        let outputTimeout = arguments.resolveOutputTimeout(
            default: XcodebuildRunner.deviceOutputTimeout,
        )

        var steps: [String] = []

        do {
            // Step 1: Look up device platform for generic destination
            let connectedDevice = try await deviceCtlRunner.lookupDevice(udid: device)
            let destination = "generic/platform=\(connectedDevice.platform)"
            let additionalArguments = arguments.continueBuildingArgs()
                + arguments.buildSettingOverrides() + extraArgs
            let derivedDataNote = DerivedDataScoper.note(
                workspacePath: workspacePath,
                projectPath: projectPath,
                destination: destination,
                additionalArguments: additionalArguments,
            )

            // Step 2: Build
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                additionalArguments: additionalArguments,
                environment: environment,
                timeout: timeout,
                outputTimeout: outputTimeout,
            )
            try ErrorExtractor.checkBuildSuccess(
                buildResult, projectRoot: nil, derivedDataNote: derivedDataNote,
            )
            steps.append("✓ Build succeeded")

            // Step 3: Extract app path and bundle ID from build settings
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                destination: destination,
                outputTimeout: outputTimeout,
            )

            // One decode serves both lookups; the payload runs to megabytes.
            let settings = BuildSettingSet(buildSettings.stdout)

            guard let appPath = settings.appPath else {
                throw MCPError.internalError(
                    "Build succeeded but could not determine .app path from build settings.",
                )
            }

            guard let bundleID = settings.bundleID else {
                throw MCPError.internalError(
                    "Build succeeded but could not determine bundle identifier from build settings.",
                )
            }

            // Step 4: Stop any running instance (ignore not-running errors)
            do {
                _ = try await deviceCtlRunner.terminate(udid: device, bundleID: bundleID)
                steps.append("✓ Stopped running instance of '\(bundleID)'")
            } catch {
                switch error {
                    case .processNotFound:
                        steps.append("– No running instance of '\(bundleID)' to stop")
                    default: steps.append("⚠ Could not stop app: \(error.localizedDescription)")
                }
            }

            // Step 5: Install
            let installResult = try await deviceCtlRunner.install(udid: device, appPath: appPath)
            guard installResult.succeeded else {
                throw MCPError.internalError("Install failed: \(installResult.errorOutput)")
            }
            steps.append("✓ Installed '\(appPath)'")

            // Step 6: Launch
            let launchResult = try await deviceCtlRunner.launch(udid: device, bundleID: bundleID)
            guard launchResult.succeeded else {
                throw MCPError.internalError("Launch failed: \(launchResult.errorOutput)")
            }
            steps.append("✓ Launched '\(bundleID)'")

            let summary = steps.joined(separator: "\n")
            return CallTool.Result.text(
                "Build and deploy succeeded for scheme '\(scheme)' on device '\(device)'\n\n\(summary)"
                    + "\n\n" + derivedDataNote)
        } catch {
            if error is CancellationError { throw error }
            let progress = steps.isEmpty ? "" : "\n\nProgress:\n\(steps.joined(separator: "\n"))"
            throw MCPError.internalError(
                "Build and deploy failed: \(error.localizedDescription)\(progress)",
            )
        }
    }
}
