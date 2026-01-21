import Foundation
import MCP

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
        // Get project/workspace path
        let projectPath: String?
        if case let .string(value) = arguments["project_path"] {
            projectPath = value
        } else {
            projectPath = await sessionManager.projectPath
        }

        let workspacePath: String?
        if case let .string(value) = arguments["workspace_path"] {
            workspacePath = value
        } else {
            workspacePath = await sessionManager.workspacePath
        }

        // Get scheme
        let scheme: String
        if case let .string(value) = arguments["scheme"] {
            scheme = value
        } else if let sessionScheme = await sessionManager.scheme {
            scheme = sessionScheme
        } else {
            throw MCPError.invalidParams(
                "scheme is required. Set it with set_session_defaults or pass it directly.")
        }

        // Get device
        let device: String
        if case let .string(value) = arguments["device"] {
            device = value
        } else if let sessionDevice = await sessionManager.deviceUDID {
            device = sessionDevice
        } else {
            throw MCPError.invalidParams(
                "device is required. Set it with set_session_defaults or pass it directly.")
        }

        // Get configuration
        let configuration: String
        if case let .string(value) = arguments["configuration"] {
            configuration = value
        } else if let sessionConfig = await sessionManager.configuration {
            configuration = sessionConfig
        } else {
            configuration = "Debug"
        }

        // Validate we have either project or workspace
        if projectPath == nil && workspacePath == nil {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly."
            )
        }

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
