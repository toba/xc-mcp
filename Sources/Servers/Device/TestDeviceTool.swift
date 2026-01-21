import Foundation
import MCP
import XCMCPCore

public struct TestDeviceTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "test_device",
            description:
                "Run tests for an Xcode project or workspace on a connected iOS/tvOS/watchOS device.",
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
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID. Uses session default if not specified."),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
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
        let device = try await sessionManager.resolveDevice(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)

        do {
            let destination = "id=\(device)"

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
                            "Tests passed for scheme '\(scheme)' on device '\(device)'\n\n\(summary)"
                        )
                    ]
                )
            } else {
                let errorOutput = extractTestFailures(from: result.output)
                throw MCPError.internalError("Tests failed:\n\(errorOutput)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Tests failed: \(error.localizedDescription)")
        }
    }

    private func extractTestSummary(from output: String) -> String {
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
            return lines.suffix(30).joined(separator: "\n")
        }

        return failureLines.joined(separator: "\n")
    }
}
