import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct TestMacOSTool: Sendable {
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
            name: "test_macos",
            description:
            "Run tests for an Xcode project or workspace on macOS.",
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
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug.",
                            ),
                        ]),
                        "arch": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Architecture to test on (arm64 or x86_64). Defaults to the current machine's architecture.",
                            ),
                        ]),
                        "errors_only": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When true, only show compiler errors, linker errors, and the build summary — all warnings are suppressed. Useful for iterating on build errors without warning noise.",
                            ),
                        ]),
                    ].merging([String: Value].testSchemaProperties) { _, new in new }
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
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let arch = arguments.getString("arch")
        let errorsOnly = arguments.getBool("errors_only")

        let testParams = arguments.testParameters()
        let (validated, warning) = try TestToolHelper.validateTestParams(
            testParams, projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
        )

        try await BuildSettingExtractor.validateMacOSSupport(
            runner: xcodebuildRunner,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            configuration: configuration,
        )

        var destination = "platform=macOS"
        if let arch {
            destination += ",arch=\(arch)"
        }

        return try await TestToolHelper.runAndFormat(
            runner: xcodebuildRunner,
            testParams: validated,
            validationWarning: warning,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            destination: destination,
            configuration: configuration,
            additionalArguments: arguments.buildSettingOverrides(),
            environment: environment,
            context: "scheme '\(scheme)' on macOS",
            errorsOnly: errorsOnly,
        )
    }
}
