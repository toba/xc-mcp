import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct BuildDeviceTool: Sendable {
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
            name: "build_device",
            description:
                "Build an Xcode project or workspace for a connected iOS/tvOS/watchOS device.",
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
        // Resolve parameters from arguments or session defaults
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

        do {
            // Look up the device to get its platform — xcodebuild doesn't recognize CoreDevice
            // UDIDs, so we build with a generic platform destination instead
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

            let result = try await xcodebuildRunner.build(
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
                result, projectRoot: nil, derivedDataNote: derivedDataNote,
            )

            // Extract the built .app path from build settings
            var appPathLine = ""
            let buildSettings = try? await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                destination: destination,
                outputTimeout: outputTimeout,
            )
            if let buildSettings,
               let appPath = BuildSettingExtractor.extractAppPath(from: buildSettings.stdout) {
                appPathLine = "\nApp path: \(appPath)"
            }

            return CallTool.Result.text(
                "Build succeeded for scheme '\(scheme)' on device '\(device)'\(appPathLine)"
                    + "\n\n" + derivedDataNote)
        } catch {
            throw try error.asMCPError()
        }
    }
}
