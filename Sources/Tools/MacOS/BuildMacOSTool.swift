import MCP
import XCMCPCore
import Foundation

public struct BuildMacOSTool: Sendable {
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
            name: "build_macos",
            description:
            "Build an Xcode project or workspace for macOS.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
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
                            "The scheme to build. Uses session default if not specified.",
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
                            "Architecture to build for (arm64 or x86_64). Defaults to the current machine's architecture.",
                        ),
                    ]),
                ]),
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
        let arch = arguments.getString("arch")

        do {
            var destination = "platform=macOS"
            if let arch {
                destination += ",arch=\(arch)"
            }

            let result = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
            )

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            // Derive project root for warning filtering
            let projectRoot: String? = if let projectPath {
                URL(fileURLWithPath: projectPath).deletingLastPathComponent().path
            } else if let workspacePath {
                URL(fileURLWithPath: workspacePath).deletingLastPathComponent().path
            } else {
                nil
            }

            if result.succeeded || buildResult.status == "success" {
                return CallTool.Result(
                    content: [
                        .text("Build succeeded for scheme '\(scheme)' on macOS"),
                        NextStepHints.content(hints: [
                            NextStepHint(
                                tool: "launch_mac_app", description: "Launch the built macOS app",
                            ),
                            NextStepHint(tool: "test_macos", description: "Run tests on macOS"),
                        ]),
                    ],
                )
            } else {
                let errorOutput = BuildResultFormatter.formatBuildResult(
                    buildResult, projectRoot: projectRoot,
                )
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
