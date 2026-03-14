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
                    ].merging([String: Value].testSchemaProperties) { _, new in new },
                ),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let arch = arguments.getString("arch")
        let errorsOnly = arguments.getBool("errors_only")

        let testParams = arguments.testParameters()

        // Always create a result bundle for detailed test results
        let resultBundlePath = testParams.resultBundlePath ?? createTempResultBundlePath()
        let isTemporaryBundle = testParams.resultBundlePath == nil

        do {
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

            let outputTimeout: Duration? =
                if let seconds = testParams.outputTimeout {
                    seconds == 0 ? nil : .seconds(seconds)
                } else {
                    XcodebuildRunner.defaultTestOutputTimeout
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
                resultBundlePath: resultBundlePath,
                testPlan: testParams.testPlan,
                environment: environment,
                timeout: TimeInterval(testParams.timeout ?? 300),
                outputTimeout: outputTimeout,
            )

            defer {
                if isTemporaryBundle {
                    try? FileManager.default.removeItem(atPath: resultBundlePath)
                }
            }

            let projectRoot = (workspacePath ?? projectPath)
                .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }

            return try await ErrorExtractor.formatTestToolResult(
                output: result.output, succeeded: result.succeeded,
                context: "scheme '\(scheme)' on macOS",
                xcresultPath: resultBundlePath,
                stderr: result.stderr,
                projectRoot: projectRoot,
                projectPath: projectPath,
                workspacePath: workspacePath,
                onlyTesting: testParams.onlyTesting,
                scheme: scheme,
                errorsOnly: errorsOnly,
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
