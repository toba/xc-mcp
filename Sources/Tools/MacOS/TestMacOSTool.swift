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
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified."),
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
                ]),
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
                configuration: configuration
            )

            if result.succeeded {
                let summary = extractTestSummary(from: result.output)
                return CallTool.Result(
                    content: [
                        .text(
                            "Tests passed for scheme '\(scheme)' on macOS\n\n\(summary)"
                        )
                    ]
                )
            } else {
                // Extract relevant error information
                let errorOutput = extractTestFailures(from: result.output)
                throw MCPError.internalError("Tests failed:\n\(errorOutput)")
            }
        } catch {
            throw error.asMCPError()
        }
    }

    private func extractTestSummary(from output: String) -> String {
        // Look for test summary lines
        let lines = output.components(separatedBy: .newlines)
        var summaryLines: [String] = []

        for line in lines {
            if line.contains("Test Suite") || line.contains("Executed")
                || line.contains("passed") || line.contains("failed")
            {
                summaryLines.append(line)
            }
        }

        if summaryLines.isEmpty {
            return "Test run completed."
        }

        return summaryLines.joined(separator: "\n")
    }

    private func extractTestFailures(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        var failureLines: [String] = []

        for line in lines {
            if line.contains("error:") || line.contains("failed")
                || line.contains("FAILED") || line.contains("TEST FAILED")
            {
                failureLines.append(line)
            }
        }

        if failureLines.isEmpty {
            // Return last 30 lines if no specific failures found
            return lines.suffix(30).joined(separator: "\n")
        }

        return failureLines.joined(separator: "\n")
    }
}
