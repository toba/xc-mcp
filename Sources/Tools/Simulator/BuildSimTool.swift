import MCP
import XCMCPCore
import Foundation
import Subprocess

/// MCP tool for building Xcode projects for the iOS/tvOS/watchOS Simulator.
///
/// Builds the specified scheme using xcodebuild with the simulator destination.
/// Supports session defaults for project, scheme, simulator, and configuration.
public struct BuildSimTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    /// Creates a new BuildSimTool instance.
    ///
    /// - Parameters:
    ///   - xcodebuildRunner: Runner for executing xcodebuild commands.
    ///   - sessionManager: Manager for session state and defaults.
    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(), sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    /// Returns the MCP tool definition.
    public func tool() -> Tool {
        Tool(
            name: "build_sim",
            description:
            "Build an Xcode project or workspace for the iOS/tvOS/watchOS Simulator.",
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
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    /// Executes the build with the given arguments.
    ///
    /// - Parameter arguments: Dictionary containing optional project_path, workspace_path, scheme, simulator, and configuration.
    /// - Returns: The result containing build success or error information.
    /// - Throws: MCPError if required parameters are missing or build fails.
    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)

        do {
            let destination = "platform=iOS Simulator,id=\(simulator)"

            let result = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                environment: environment,
            )

            let projectRoot = ErrorExtractor.projectRoot(
                projectPath: projectPath, workspacePath: workspacePath,
            )
            try ErrorExtractor.checkBuildSuccess(result, projectRoot: projectRoot)

            return CallTool.Result(
                content: [
                    .text("Build succeeded for scheme '\(scheme)' on simulator '\(simulator)'"),
                ],
            )
        } catch {
            throw error.asMCPError()
        }
    }
}
