import Foundation
import MCP
import XCMCPCore

public struct DebugDetachTool: Sendable {
  private let lldbRunner: LLDBRunner

  public init(lldbRunner: LLDBRunner = LLDBRunner()) {
    self.lldbRunner = lldbRunner
  }

  public func tool() -> Tool {
    Tool(
      name: "debug_detach",
      description:
        "Detach the LLDB debugger from a process.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string(
              "Bundle identifier of the app to detach from.",
            ),
          ]),
          "pid": .object([
            "type": .string("integer"),
            "description": .string(
              "Process ID to detach from.",
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
        "Either bundle_id (with active session) or pid is required",
      )
    }

    do {
      let result = try await lldbRunner.detach(pid: targetPID)

      var message = "Detached from process \(targetPID)"
      if !result.output.isEmpty {
        message += "\n\n\(result.output)"
      }

      return CallTool.Result(content: [.text(message)])
    } catch {
      throw error.asMCPError()
    }
  }
}
