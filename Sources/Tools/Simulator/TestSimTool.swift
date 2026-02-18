import Foundation
import MCP
import XCMCPCore

public struct TestSimTool: Sendable {
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
                        "simulator": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Simulator UDID or name. Uses session default if not specified."),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug."),
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
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)

        let testParams = arguments.testParameters()

        // Always create a result bundle for detailed test results
        let resultBundlePath = testParams.resultBundlePath ?? createTempResultBundlePath()
        let isTemporaryBundle = testParams.resultBundlePath == nil

        do {
            let destination = "platform=iOS Simulator,id=\(simulator)"

            let result = try await xcodebuildRunner.test(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                onlyTesting: testParams.onlyTesting,
                skipTesting: testParams.skipTesting,
                enableCodeCoverage: testParams.enableCodeCoverage,
                resultBundlePath: resultBundlePath
            )

            defer {
                if isTemporaryBundle {
                    try? FileManager.default.removeItem(atPath: resultBundlePath)
                }
            }

            return try ErrorExtractor.formatTestToolResult(
                output: result.output, succeeded: result.succeeded,
                context: "scheme '\(scheme)' on simulator '\(simulator)'",
                xcresultPath: resultBundlePath,
                stderr: result.stderr
            )
        } catch {
            if isTemporaryBundle {
                try? FileManager.default.removeItem(atPath: resultBundlePath)
            }
            throw error.asMCPError()
        }
    }

}

private func createTempResultBundlePath() -> String {
    let tempDir = FileManager.default.temporaryDirectory.path
    return "\(tempDir)/xc-mcp-test-\(UUID().uuidString).xcresult"
}
