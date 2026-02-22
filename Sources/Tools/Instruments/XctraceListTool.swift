import Foundation
import MCP
import XCMCPCore

/// Lists available Instruments templates, instruments, or devices.
///
/// This tool queries `xctrace list` to show what profiling templates,
/// instruments, or devices are available on the system.
public struct XctraceListTool: Sendable {
  private let xctraceRunner: XctraceRunner

  public init(xctraceRunner: XctraceRunner = XctraceRunner()) {
    self.xctraceRunner = xctraceRunner
  }

  public func tool() -> Tool {
    Tool(
      name: "xctrace_list",
      description:
        "List available Instruments templates, instruments, or devices via xctrace.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "kind": .object([
            "type": .string("string"),
            "enum": .array([
              .string("templates"), .string("instruments"), .string("devices"),
            ]),
            "description": .string(
              "What to list: 'templates' for profiling templates, 'instruments' for available instruments, 'devices' for connected devices.",
            ),
          ])
        ]),
        "required": .array([.string("kind")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    guard case .string(let kind) = arguments["kind"] else {
      throw MCPError.invalidParams("kind is required")
    }

    guard ["templates", "instruments", "devices"].contains(kind) else {
      throw MCPError.invalidParams(
        "Invalid kind: \(kind). Use 'templates', 'instruments', or 'devices'.",
      )
    }

    do {
      let result = try await xctraceRunner.list(kind: kind)

      guard result.succeeded else {
        throw MCPError.internalError("xctrace list \(kind) failed: \(result.stderr)")
      }

      let output = result.stdout.isEmpty ? result.stderr : result.stdout
      return CallTool.Result(content: [.text(output)])
    } catch let error as MCPError {
      throw error
    } catch {
      throw MCPError.internalError(
        "Failed to list \(kind): \(error.localizedDescription)",
      )
    }
  }
}
