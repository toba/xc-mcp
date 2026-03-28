import MCP
import Foundation
import Subprocess

/// Shared logic for test tools (test_sim, test_macos, test_device).
///
/// Handles `only_testing` pre-validation, temporary result bundle lifecycle,
/// `formatTestToolResult` invocation, and validation warning prepending.
public enum TestToolHelper {
    /// Validates `only_testing` entries and returns updated test parameters
    /// along with an optional warning about removed entries.
    public static func validateTestParams(
        _ testParams: TestParameters,
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
    ) throws -> (params: TestParameters, warning: String?) {
        guard let onlyTesting = testParams.onlyTesting, !onlyTesting.isEmpty else {
            return (testParams, nil)
        }
        let projectRoot = (workspacePath ?? projectPath)
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        guard let projectRoot else {
            return (testParams, nil)
        }

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
            let updated = TestParameters(
                onlyTesting: validation.valid,
                skipTesting: testParams.skipTesting,
                enableCodeCoverage: testParams.enableCodeCoverage,
                resultBundlePath: testParams.resultBundlePath,
                testPlan: testParams.testPlan,
                timeout: testParams.timeout,
                outputTimeout: testParams.outputTimeout,
            )
            return (updated, validation.warning)
        }
        return (testParams, nil)
    }

    /// Resolves the output timeout from test parameters, applying the default
    /// when not specified and disabling when explicitly set to zero.
    public static func resolveOutputTimeout(
        _ testParams: TestParameters,
    ) -> Duration? {
        if let seconds = testParams.outputTimeout {
            seconds == 0 ? nil : .seconds(seconds)
        } else {
            XcodebuildRunner.defaultTestOutputTimeout
        }
    }

    /// Runs xcodebuild test, formats results, and manages the temporary result bundle.
    ///
    /// - Parameters:
    ///   - runner: The xcodebuild runner to use.
    ///   - testParams: Validated test parameters.
    ///   - validationWarning: Optional warning from `validateTestParams` to prepend.
    ///   - projectPath: Path to .xcodeproj (or nil).
    ///   - workspacePath: Path to .xcworkspace (or nil).
    ///   - scheme: The scheme to test.
    ///   - destination: The xcodebuild destination string.
    ///   - configuration: Build configuration (Debug/Release).
    ///   - environment: Environment for the test run.
    ///   - context: Human-readable context for error messages (e.g. "on simulator 'X'").
    ///   - errorsOnly: When true, suppress warnings in output.
    public static func runAndFormat(
        runner: XcodebuildRunner,
        testParams: TestParameters,
        validationWarning: String?,
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
        destination: String,
        configuration: String = "Debug",
        additionalArguments: [String] = [],
        environment: Environment = .inherit,
        context: String,
        errorsOnly: Bool = false,
    ) async throws -> CallTool.Result {
        let resultBundlePath = testParams.resultBundlePath ?? createTempResultBundlePath()
        let isTemporaryBundle = testParams.resultBundlePath == nil

        do {
            let outputTimeout = resolveOutputTimeout(testParams)

            let result = try await runner.test(
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
                additionalArguments: additionalArguments,
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
                context: context,
                xcresultPath: resultBundlePath,
                stderr: result.stderr,
                projectRoot: projectRoot,
                projectPath: projectPath,
                workspacePath: workspacePath,
                onlyTesting: testParams.onlyTesting,
                scheme: scheme,
                errorsOnly: errorsOnly,
            )

            if let validationWarning {
                toolResult = CallTool.Result(
                    content: [.text(validationWarning)] + toolResult.content,
                    isError: toolResult.isError,
                )
            }

            return toolResult
        } catch let error as XcodebuildError {
            if isTemporaryBundle {
                try? FileManager.default.removeItem(atPath: resultBundlePath)
            }
            let projectRoot = (workspacePath ?? projectPath)
                .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
            return error.formatPartialDiagnostics(
                projectRoot: projectRoot, errorsOnly: errorsOnly,
            )
        } catch {
            if isTemporaryBundle {
                try? FileManager.default.removeItem(atPath: resultBundlePath)
            }
            throw error.asMCPError()
        }
    }

    private static func createTempResultBundlePath() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        return "\(tempDir)/xc-mcp-test-\(UUID().uuidString).xcresult"
    }
}
