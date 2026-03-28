import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct TestSimTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(), sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "test_sim",
            description:
            "Run tests for an Xcode project or workspace on the iOS/tvOS/watchOS Simulator.",
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
                        "simulator": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Simulator UDID or name. Uses session default if not specified.",
                            ),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug.",
                            ),
                        ]),
                    ].merging([String: Value].testSchemaProperties) { _, new in new }
                        .merging([String: Value].continueBuildingSchemaProperty) { _, new in new }
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
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)

        let testParams = arguments.testParameters()
        let (validated, warning) = try TestToolHelper.validateTestParams(
            testParams, projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
        )

        return try await TestToolHelper.runAndFormat(
            runner: xcodebuildRunner,
            testParams: validated,
            validationWarning: warning,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            destination: "platform=iOS Simulator,id=\(simulator)",
            configuration: configuration,
            additionalArguments: arguments.continueBuildingArgs() + arguments
                .buildSettingOverrides(),
            environment: environment,
            context: "scheme '\(scheme)' on simulator '\(simulator)'",
        )
    }
}
