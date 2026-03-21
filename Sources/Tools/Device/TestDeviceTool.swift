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
        let device = try await sessionManager.resolveDevice(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)

        var testParams = arguments.testParameters()

        // Pre-validate only_testing entries to avoid xcodebuild rejecting the entire run
        var validationWarning: String?
        if let onlyTesting = testParams.onlyTesting, !onlyTesting.isEmpty {
            let projectRoot = (workspacePath ?? projectPath)
                .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
            if let projectRoot {
                let validation = ErrorExtractor.validateOnlyTesting(
                    onlyTesting,
                    projectRoot: projectRoot,
                    projectPath: projectPath,
                    workspacePath: workspacePath,
                    scheme: scheme,
                )
                if validation.valid.isEmpty {
                    throw MCPError.invalidParams(
                        "All only_testing entries are invalid. " + (validation.warning ?? ""),
                    )
                }
                if validation.valid.count < onlyTesting.count {
                    testParams = TestParameters(
                        onlyTesting: validation.valid,
                        skipTesting: testParams.skipTesting,
                        enableCodeCoverage: testParams.enableCodeCoverage,
                        resultBundlePath: testParams.resultBundlePath,
                        testPlan: testParams.testPlan,
                        timeout: testParams.timeout,
                        outputTimeout: testParams.outputTimeout,
                    )
                    validationWarning = validation.warning
                }
            }
        }

        // Always create a result bundle for detailed test results
        let resultBundlePath = testParams.resultBundlePath ?? createTempResultBundlePath()
        let isTemporaryBundle = testParams.resultBundlePath == nil

        do {
            // Look up the device to get its platform — xcodebuild doesn't recognize
            // CoreDevice UDIDs, so we build with a generic platform destination instead
            let connectedDevice = try await deviceCtlRunner.lookupDevice(udid: device)
            let destination = "generic/platform=\(connectedDevice.platform)"

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

            var toolResult = try await ErrorExtractor.formatTestToolResult(
                output: result.output, succeeded: result.succeeded,
                context: "scheme '\(scheme)' on device '\(device)'",
                xcresultPath: resultBundlePath,
                stderr: result.stderr,
                projectRoot: projectRoot,
                projectPath: projectPath,
                workspacePath: workspacePath,
                onlyTesting: testParams.onlyTesting,
                scheme: scheme,
            )

            if let validationWarning {
                toolResult = CallTool.Result(
                    content: [.text(validationWarning)] + toolResult.content,
                )
            }

            return toolResult
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
