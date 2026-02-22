import Foundation
import MCP
import XCMCPCore

public struct DebugBreakpointAddTool: Sendable {
  private let lldbRunner: LLDBRunner

  public init(lldbRunner: LLDBRunner = LLDBRunner()) {
    self.lldbRunner = lldbRunner
  }

  public func tool() -> Tool {
    Tool(
      name: "debug_breakpoint_add",
      description:
        "Add a breakpoint to a debugging session.",
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
          "symbol": .object([
            "type": .string("string"),
            "description": .string(
              "Function or method name to break at (e.g., 'viewDidLoad').",
            ),
          ]),
          "file": .object([
            "type": .string("string"),
            "description": .string(
              "Source file path for file:line breakpoint.",
            ),
          ]),
          "line": .object([
            "type": .string("integer"),
            "description": .string(
              "Line number for file:line breakpoint.",
            ),
          ]),
        ]),
        "required": .array([]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    // Get PID
    var pid = arguments.getInt("pid").map(Int32.init)

    if pid == nil, let bundleId = arguments.getString("bundle_id") {
      pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
    }

    guard let targetPID = pid else {
      throw MCPError.invalidParams(
        "Either pid or bundle_id (with active session) is required",
      )
    }

    // Get breakpoint location
    let symbol = arguments.getString("symbol")
    let file = arguments.getString("file")
    let line = arguments.getInt("line")

    // Validate we have a location
    if symbol == nil, file == nil || line == nil {
      throw MCPError.invalidParams(
        "Either 'symbol' or both 'file' and 'line' are required to set a breakpoint",
      )
    }

    do {
      let result: LLDBResult
      if let symbol {
        result = try await lldbRunner.setBreakpoint(pid: targetPID, symbol: symbol)
      } else if let file, let line {
        result = try await lldbRunner.setBreakpoint(pid: targetPID, file: file, line: line)
      } else {
        throw MCPError.invalidParams("Invalid breakpoint specification")
      }

      var message = "Breakpoint added"
      if let symbol {
        message += " at symbol '\(symbol)'"
      } else if let file, let line {
        message += " at \(file):\(line)"
      }
      message += "\n\n\(result.output)"

      return CallTool.Result(content: [.text(message)])
    } catch {
      throw error.asMCPError()
    }
  }
}
