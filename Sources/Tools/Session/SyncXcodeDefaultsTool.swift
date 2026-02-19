import Foundation
import MCP
import XCMCPCore

public struct SyncXcodeDefaultsTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "sync_xcode_defaults",
            description:
                "Read the active scheme and run destination from Xcode's IDE state and apply them as session defaults. Requires the project to have been opened in Xcode.",
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
                            "Path to the .xcworkspace file. Uses session default if not specified."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve the project/workspace path
        let projectPath: String?
        if let argProject = arguments.getString("project_path") {
            projectPath = argProject
        } else {
            projectPath = await sessionManager.projectPath
        }
        let workspacePath: String?
        if let argWorkspace = arguments.getString("workspace_path") {
            workspacePath = argWorkspace
        } else {
            workspacePath = await sessionManager.workspacePath
        }

        let targetPath = workspacePath ?? projectPath
        guard let targetPath else {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly."
            )
        }

        let state = XcodeStateReader.readState(projectOrWorkspacePath: targetPath)

        if let error = state.error, state.scheme == nil && state.simulatorUDID == nil {
            return CallTool.Result(
                content: [
                    .text(
                        "Could not sync Xcode state: \(error)\n\nUse set_session_defaults to configure manually."
                    )
                ],
                isError: true
            )
        }

        // Apply discovered state to session
        var synced: [String] = []

        if let scheme = state.scheme {
            await sessionManager.setDefaults(scheme: scheme)
            synced.append("Scheme: \(scheme)")
        }
        if let udid = state.simulatorUDID {
            await sessionManager.setDefaults(simulatorUDID: udid)
            let name = state.simulatorName ?? udid
            synced.append("Simulator: \(name) (\(udid))")
        }

        // Also ensure the project path is set
        let hasProjectPath = await sessionManager.projectPath != nil
        let hasWorkspacePath = await sessionManager.workspacePath != nil
        if !hasProjectPath && !hasWorkspacePath {
            if targetPath.hasSuffix(".xcworkspace") {
                await sessionManager.setDefaults(workspacePath: targetPath)
                synced.append("Workspace: \(targetPath)")
            } else {
                await sessionManager.setDefaults(projectPath: targetPath)
                synced.append("Project: \(targetPath)")
            }
        }

        var message = "Synced from Xcode IDE state:\n"
        message += synced.map { "  \($0)" }.joined(separator: "\n")

        if let error = state.error {
            message += "\n\nPartial sync (some fields could not be read): \(error)"
        }

        return CallTool.Result(content: [
            .text(message),
            NextStepHints.content(hints: [
                NextStepHint(tool: "build_sim", description: "Build for the simulator"),
                NextStepHint(tool: "build_macos", description: "Build for macOS"),
            ]),
        ])
    }
}
