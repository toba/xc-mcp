import Foundation
import MCP
import XCMCPCore

public struct StopMacAppTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "stop_mac_app",
            description:
                "Stop (terminate) a running macOS app by its bundle identifier or app name.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to stop (e.g., 'com.example.MyApp')."),
                    ]),
                    "app_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the app to stop (e.g., 'MyApp'). Alternative to bundle_id."),
                    ]),
                    "force": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, forcefully terminates the app (SIGKILL). Defaults to false (SIGTERM)."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundleId: String?
        if case let .string(value) = arguments["bundle_id"] {
            bundleId = value
        } else {
            bundleId = nil
        }

        let appName: String?
        if case let .string(value) = arguments["app_name"] {
            appName = value
        } else {
            appName = nil
        }

        // Validate we have either bundle_id or app_name
        if bundleId == nil && appName == nil {
            throw MCPError.invalidParams("Either bundle_id or app_name is required.")
        }

        let force: Bool
        if case let .bool(value) = arguments["force"] {
            force = value
        } else {
            force = false
        }

        do {
            let process = Process()

            if let bundleId {
                // Use osascript to quit app by bundle ID gracefully, or pkill for force
                if force {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                    process.arguments = ["-9", "-f", bundleId]
                } else {
                    // Try graceful quit first using AppleScript
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = [
                        "-e",
                        "tell application id \"\(bundleId)\" to quit",
                    ]
                }
            } else if let appName {
                if force {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                    process.arguments = ["-9", appName]
                } else {
                    // Try graceful quit first using AppleScript
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = [
                        "-e",
                        "tell application \"\(appName)\" to quit",
                    ]
                }
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            let identifier = bundleId ?? appName ?? "unknown"

            // For osascript, exit status 0 means success
            // For pkill, exit status 0 means at least one process was killed
            // Exit status 1 for pkill means no processes matched (not necessarily an error)
            if process.terminationStatus == 0 {
                var message = "Successfully stopped '\(identifier)'"
                if force {
                    message += " (forced)"
                }
                return CallTool.Result(content: [.text(message)])
            } else {
                // Check if the app just wasn't running
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if output.isEmpty || output.contains("no matching")
                    || process.terminationStatus == 1
                {
                    return CallTool.Result(
                        content: [.text("App '\(identifier)' was not running")]
                    )
                }

                throw MCPError.internalError("Failed to stop app: \(output)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to stop app: \(error.localizedDescription)")
        }
    }
}
