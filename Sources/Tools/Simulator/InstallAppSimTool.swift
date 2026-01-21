import Foundation
import MCP

public struct InstallAppSimTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "install_app_sim",
            description: "Install an app (.app bundle) on a simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .app bundle to install."),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                ]),
                "required": .array([.string("app_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let appPath = try arguments.getRequiredString("app_path")
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        do {
            let result = try await simctlRunner.install(udid: simulator, appPath: appPath)

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully installed app at '\(appPath)' on simulator '\(simulator)'"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to install app: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to install app: \(error.localizedDescription)")
        }
    }
}
