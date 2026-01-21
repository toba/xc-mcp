import Foundation
import MCP

public struct BuildMacOSTool: Sendable {
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
            name: "build_macos",
            description:
                "Build an Xcode project or workspace for macOS.",
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
                            "The scheme to build. Uses session default if not specified."),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                    "arch": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Architecture to build for (arm64 or x86_64). Defaults to the current machine's architecture."
                        ),
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

        // Get configuration
        let configuration: String
        if case let .string(value) = arguments["configuration"] {
            configuration = value
        } else if let sessionConfig = await sessionManager.configuration {
            configuration = sessionConfig
        } else {
            configuration = "Debug"
        }

        // Get architecture (optional)
        let arch: String?
        if case let .string(value) = arguments["arch"] {
            arch = value
        } else {
            arch = nil
        }

        // Validate we have either project or workspace
        if projectPath == nil && workspacePath == nil {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly."
            )
        }

        do {
            var destination = "platform=macOS"
            if let arch = arch {
                destination += ",arch=\(arch)"
            }

            let result = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration
            )

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text("Build succeeded for scheme '\(scheme)' on macOS")
                    ]
                )
            } else {
                // Extract relevant error information
                let errorOutput = extractBuildErrors(from: result.output)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Build failed: \(error.localizedDescription)")
        }
    }

    private func extractBuildErrors(from output: String) -> String {
        // Extract lines containing "error:" for more concise error reporting
        let lines = output.components(separatedBy: .newlines)
        let errorLines = lines.filter {
            $0.contains("error:") || $0.contains("BUILD FAILED")
        }

        if errorLines.isEmpty {
            // Return last 20 lines if no specific errors found
            return lines.suffix(20).joined(separator: "\n")
        }

        return errorLines.joined(separator: "\n")
    }
}
