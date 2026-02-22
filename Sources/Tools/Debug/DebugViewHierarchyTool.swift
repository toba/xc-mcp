import Foundation
import MCP
import XCMCPCore

public struct DebugViewHierarchyTool: Sendable {
  private let lldbRunner: LLDBRunner

  public init(lldbRunner: LLDBRunner = LLDBRunner()) {
    self.lldbRunner = lldbRunner
  }

  public func tool() -> Tool {
    Tool(
      name: "debug_view_hierarchy",
      description:
        "Dump the UI view hierarchy of a running app.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "pid": .object([
            "type": .string("integer"),
            "description": .string(
              "Process ID of the debugged process.",
            ),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string(
              "Bundle identifier of the app (uses registered session).",
            ),
          ]),
          "platform": .object([
            "type": .string("string"),
            "description": .string(
              "Platform: 'ios' (default) or 'macos'.",
            ),
          ]),
          "address": .object([
            "type": .string("string"),
            "description": .string(
              "Specific view address to inspect. Omit for root view hierarchy.",
            ),
          ]),
          "constraints": .object([
            "type": .string("boolean"),
            "description": .string(
              "Show Auto Layout constraints for the view. Defaults to false.",
            ),
          ]),
        ]),
        "required": .array([]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    var pid = arguments.getInt("pid").map(Int32.init)

    if pid == nil, let bundleId = arguments.getString("bundle_id") {
      pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
    }

    guard let targetPID = pid else {
      throw MCPError.invalidParams(
        "Either pid or bundle_id (with active session) is required",
      )
    }

    let platform = arguments.getString("platform") ?? "ios"
    let address = arguments.getString("address")
    let constraints = arguments.getBool("constraints")

    do {
      let result = try await lldbRunner.viewHierarchy(
        pid: targetPID,
        platform: platform,
        address: address,
        constraints: constraints,
      )

      let message = "View hierarchy:\n\n\(result.output)"
      return CallTool.Result(content: [.text(message)])
    } catch {
      throw error.asMCPError()
    }
  }
}
