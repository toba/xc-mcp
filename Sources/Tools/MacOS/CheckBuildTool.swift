import Foundation
import MCP
import XCMCPCore

public struct CheckBuildTool: Sendable {
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
            name: "check_build",
            description:
                "Build a single Xcode target for fast compilation checking. Uses -target instead of -scheme to compile just one target without building the full scheme dependency graph. Useful for catching type errors and missing imports in auxiliary targets (e.g. test support modules) without a full build.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The name of the target to build."),
                    ]),
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
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build destination. Defaults to 'platform=macOS'."),
                    ]),
                ]),
                "required": .array([.string("target_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard let targetName = arguments.getString("target_name") else {
            throw MCPError.invalidParams("target_name is required")
        }

        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let destination = arguments.getString("destination") ?? "platform=macOS"

        do {
            let result = try await xcodebuildRunner.buildTarget(
                projectPath: projectPath,
                workspacePath: workspacePath,
                target: targetName,
                destination: destination,
                configuration: configuration
            )

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            if result.succeeded || buildResult.status == "success" {
                return CallTool.Result(
                    content: [
                        .text("Build succeeded for target '\(targetName)'"),
                        NextStepHints.content(hints: [
                            NextStepHint(
                                tool: "build_macos",
                                description: "Build the full scheme for macOS"),
                            NextStepHint(tool: "test_macos", description: "Run tests on macOS"),
                        ]),
                    ]
                )
            } else {
                let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
                throw MCPError.internalError("Build failed for target '\(targetName)':\n\(errorOutput)")
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
