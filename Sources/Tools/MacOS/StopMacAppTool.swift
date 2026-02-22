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
              "Bundle identifier of the app to stop (e.g., 'com.example.MyApp').",
            ),
          ]),
          "app_name": .object([
            "type": .string("string"),
            "description": .string(
              "Name of the app to stop (e.g., 'MyApp'). Alternative to bundle_id.",
            ),
          ]),
          "force": .object([
            "type": .string("boolean"),
            "description": .string(
              "If true, forcefully terminates the app (SIGKILL). Defaults to false (SIGTERM).",
            ),
          ]),
        ]),
        "required": .array([]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let bundleId = arguments.getString("bundle_id")
    let appName = arguments.getString("app_name")

    // Validate we have either bundle_id or app_name
    if bundleId == nil, appName == nil {
      throw MCPError.invalidParams("Either bundle_id or app_name is required.")
    }

    let force = arguments.getBool("force")

    do {
      let executablePath: String
      let processArgs: [String]

      if let bundleId {
        if force {
          executablePath = "/usr/bin/pkill"
          processArgs = ["-9", "-f", bundleId]
        } else {
          executablePath = "/usr/bin/osascript"
          processArgs = ["-e", "tell application id \"\(bundleId)\" to quit"]
        }
      } else if let appName {
        if force {
          executablePath = "/usr/bin/pkill"
          processArgs = ["-9", appName]
        } else {
          executablePath = "/usr/bin/osascript"
          processArgs = ["-e", "tell application \"\(appName)\" to quit"]
        }
      } else {
        throw MCPError.invalidParams("Either bundle_id or app_name is required")
      }

      let result = try await ProcessResult.run(executablePath, arguments: processArgs)

      let identifier = bundleId ?? appName ?? "unknown"

      // For osascript, exit status 0 means success
      // For pkill, exit status 0 means at least one process was killed
      // Exit status 1 for pkill means no processes matched (not necessarily an error)
      if result.succeeded {
        var message = "Successfully stopped '\(identifier)'"
        if force {
          message += " (forced)"
        }
        return CallTool.Result(content: [.text(message)])
      } else {
        // Check if the app just wasn't running
        if result.stdout.isEmpty || result.stdout.contains("no matching")
          || result.exitCode == 1
        {
          return CallTool.Result(
            content: [.text("App '\(identifier)' was not running")],
          )
        }

        throw MCPError.internalError("Failed to stop app: \(result.stdout)")
      }
    } catch {
      throw error.asMCPError()
    }
  }
}
