import Foundation
import MCP
import XCMCPCore

public struct TestMacOSTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(), sessionManager: SessionManager
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
                                "Path to the .xcodeproj file. Uses session default if not specified."
                            ),
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
                                "The scheme to test. Uses session default if not specified."),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug."),
                        ]),
                        "arch": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Architecture to test on (arm64 or x86_64). Defaults to the current machine's architecture."
                            ),
                        ]),
                    ].merging([String: Value].testSchemaProperties) { _, new in new }),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments)
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let arch = arguments.getString("arch")

        let testParams = arguments.testParameters()

        do {
            var destination = "platform=macOS"
            if let arch {
                destination += ",arch=\(arch)"
            }

            let result = try await xcodebuildRunner.test(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                onlyTesting: testParams.onlyTesting,
                skipTesting: testParams.skipTesting,
                enableCodeCoverage: testParams.enableCodeCoverage,
                resultBundlePath: testParams.resultBundlePath
            )

            return try ErrorExtractor.formatTestToolResult(
                output: result.output, succeeded: result.succeeded,
                context: "scheme '\(scheme)' on macOS"
            )
        } catch {
            throw error.asMCPError()
        }
    }

}
