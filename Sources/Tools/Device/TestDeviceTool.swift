import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct TestDeviceTool: Sendable {
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
            name: "test_device",
            description:
            "Run tests for an Xcode project or workspace on a connected iOS/tvOS/watchOS device.",
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
                                "The scheme to test. Uses session default if not specified.",
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
                    ].merging([String: Value].testSchemaProperties) { _, new in new }
                        .merging([String: Value].buildSettingsSchemaProperty) { _, new in new },
                ),
                "required": .array([]),
            ]),
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

        let testParams = arguments.testParameters()
        let (validated, warning) = try TestToolHelper.validateTestParams(
            testParams, projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
        )

        // Look up the device to get its platform — xcodebuild doesn't recognize
        // CoreDevice UDIDs, so we build with a generic platform destination instead
        let connectedDevice = try await deviceCtlRunner.lookupDevice(udid: device)

        return try await TestToolHelper.runAndFormat(
            runner: xcodebuildRunner,
            testParams: validated,
            validationWarning: warning,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            destination: "generic/platform=\(connectedDevice.platform)",
            configuration: configuration,
            additionalArguments: arguments.buildSettingOverrides(),
            environment: environment,
            context: "scheme '\(scheme)' on device '\(device)'",
        )
    }
}
