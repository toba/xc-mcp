import MCP
import XCMCPCore
import Foundation

public struct LaunchAppSimTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
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
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleId = try arguments.getRequiredString("bundle_id")
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        let waitForDebugger = arguments.getBool("wait_for_debugger")
        let launchArgs = arguments.getStringArray("args")

        do {
            let result = try await simctlRunner.launch(
                udid: simulator,
                bundleId: bundleId,
                waitForDebugger: waitForDebugger,
                args: launchArgs,
            )

            if result.succeeded {
                var message = "Successfully launched '\(bundleId)' on simulator '\(simulator)'"
                if waitForDebugger {
                    message += "\nApp is waiting for debugger to attach."
                }
                // Extract PID if available
                if let pid = result.launchedPID {
                    message += "\nProcess ID: \(pid)"
                }
                return CallTool.Result(content: [
                    .text(message),
                    NextStepHints.content(hints: [
                        NextStepHint(
                            tool: "screenshot",
                            description: "Take a screenshot to verify the result",
                        ),
                        NextStepHint(
                            tool: "tap", description: "Tap a UI element (provide x, y coordinates)",
                        ),
                        NextStepHint(
                            tool: "debug_attach_sim",
                            description: "Attach the debugger to the running app",
                        ),
                    ]),
                ])
            } else {
                throw MCPError.internalError(
                    "Failed to launch app: \(result.errorOutput)",
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
