import MCP
import XCMCPCore
import Foundation

public struct LaunchMacAppTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "launch_mac_app",
            description:
            "Launch a macOS app by its path or bundle identifier.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .app bundle to launch (e.g., '/path/to/MyApp.app').",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to launch (e.g., 'com.example.MyApp'). Alternative to app_path.",
                        ),
                    ]),
                    "new_instance": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, launches a new instance even if the app is already running. Defaults to false.",
                        ),
                    ]),
                    "hide": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, launches the app hidden (in background). Defaults to false.",
                        ),
                    ]),
                    "wait": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, waits for the app to exit before returning. Defaults to false.",
                        ),
                    ]),
                    "args": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional arguments to pass to the app."),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let appPath = arguments.getString("app_path")
        let bundleId = arguments.getString("bundle_id")

        // Validate we have either app_path or bundle_id
        if appPath == nil, bundleId == nil {
            throw MCPError.invalidParams("Either app_path or bundle_id is required.")
        }

        let newInstance = arguments.getBool("new_instance")
        let hide = arguments.getBool("hide")
        let wait = arguments.getBool("wait")

        var launchArgs: [String] = []
        if case let .array(argsArray) = arguments["args"] {
            for arg in argsArray {
                if case let .string(argValue) = arg {
                    launchArgs.append(argValue)
                }
            }
        }

        do {
            var openArgs: [String] = []

            if let bundleId {
                openArgs.append("-b")
                openArgs.append(bundleId)
            } else if let appPath {
                openArgs.append(appPath)
            }

            if newInstance {
                openArgs.append("-n")
            }

            if hide {
                openArgs.append("-g")
            }

            if wait {
                openArgs.append("-W")
            }

            if !launchArgs.isEmpty {
                openArgs.append("--args")
                openArgs.append(contentsOf: launchArgs)
            }

            let result = try ProcessResult.run("/usr/bin/open", arguments: openArgs)

            if result.succeeded {
                let identifier = bundleId ?? appPath ?? "unknown"
                var message = "Successfully launched '\(identifier)'"
                if newInstance {
                    message += " (new instance)"
                }
                if hide {
                    message += " (hidden)"
                }
                return CallTool.Result(content: [
                    .text(message),
                    NextStepHints.content(hints: [
                        NextStepHint(
                            tool: "screenshot_mac_window",
                            description: "Take a screenshot of a macOS window",
                        ),
                        NextStepHint(
                            tool: "interact_ui_tree",
                            description: "Inspect the app's accessibility UI tree",
                        ),
                    ]),
                ])
            } else {
                throw MCPError.internalError("Failed to launch app: \(result.stdout)")
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
