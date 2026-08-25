import MCP
import XCMCPCore
import Foundation

public struct LaunchAppSimTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = .init(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "launch_app_sim",
            description: "Launch an app on a simulator by its bundle identifier.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app to launch (e.g., 'com.example.MyApp').",
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "wait_for_debugger": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, the app will wait for a debugger to attach before continuing. Defaults to false.",
                        ),
                    ]),
                    "args": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional arguments to pass to the app."),
                    ]),
                ]),
                "required": .array([.string("bundle_id")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleID = try arguments.getRequiredString("bundle_id")
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        let waitForDebugger = arguments.getBool("wait_for_debugger")
        let launchArgs = arguments.getStringArray("args")

        do {
            let result = try await simctlRunner.launch(
                udid: simulator,
                bundleID: bundleID,
                waitForDebugger: waitForDebugger,
                args: launchArgs,
            )

            if result.succeeded {
                var message = "Successfully launched '\(bundleID)' on simulator '\(simulator)'"
                if waitForDebugger { message += "\nApp is waiting for debugger to attach." }
                // Extract PID if available
                if let pid = result.launchedPID { message += "\nProcess ID: \(pid)" }
                return CallTool.Result.text(message)
            } else {
                throw MCPError.internalError("Failed to launch app: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
