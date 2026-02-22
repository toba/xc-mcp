import Foundation
import MCP
import XCMCPCore

public struct BuildDeviceTool: Sendable {
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
            name: "build_device",
            description:
                "Build an Xcode project or workspace for a connected iOS/tvOS/watchOS device.",
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

            let result = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration
            )

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            if result.succeeded || buildResult.status == "success" {
                return CallTool.Result(
                    content: [
                        .text("Build succeeded for scheme '\(scheme)' on device '\(device)'")
                    ]
                )
            } else {
                let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
