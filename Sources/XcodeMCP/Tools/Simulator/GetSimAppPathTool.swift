import Foundation
import MCP

public struct GetSimAppPathTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "get_sim_app_path",
            description:
                "Get the path to an app's container on a simulator. Useful for finding where the app is installed or its data directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app (e.g., 'com.example.MyApp')."),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "container": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The container type: 'app' (the .app bundle), 'data' (the app's data directory), 'groups' (app groups), or a specific app group identifier. Defaults to 'app'."
                        ),
                    ]),
                ]),
                "required": .array([.string("bundle_id")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(bundleId) = arguments["bundle_id"] else {
            throw MCPError.invalidParams("bundle_id is required")
        }

        // Get simulator
        let simulator: String
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else if let sessionSimulator = await sessionManager.simulatorUDID {
            simulator = sessionSimulator
        } else {
            throw MCPError.invalidParams(
                "simulator is required. Set it with set_session_defaults or pass it directly.")
        }

        let container: String
        if case let .string(value) = arguments["container"] {
            container = value
        } else {
            container = "app"
        }

        do {
            let path = try await simctlRunner.getAppContainer(
                udid: simulator,
                bundleId: bundleId,
                container: container
            )

            return CallTool.Result(
                content: [
                    .text(
                        "App container path for '\(bundleId)' (\(container)):\n\(path)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to get app container path: \(error.localizedDescription)")
        }
    }
}
