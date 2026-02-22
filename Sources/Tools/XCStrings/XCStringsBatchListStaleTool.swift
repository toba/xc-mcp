import Foundation
import MCP
import XCMCPCore

public struct XCStringsBatchListStaleTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "xcstrings_batch_list_stale",
      description:
        "List keys with extractionState 'stale' across multiple xcstrings files",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "files": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string("Array of paths to xcstrings files"),
          ])
        ]),
        "required": .array([.string("files")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) throws -> CallTool.Result {
    let files = arguments.getStringArray("files")
    if files.isEmpty {
      throw MCPError.invalidParams("files array is required and cannot be empty")
    }

    do {
      let resolvedPaths = try files.map { try pathUtility.resolvePath(from: $0) }
      let summary = try XCStringsParser.batchListStaleKeys(paths: resolvedPaths)

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(summary)
      let json = String(data: data, encoding: .utf8) ?? "{}"

      return CallTool.Result(content: [.text(json)])
    } catch let error as XCStringsError {
      throw error.toMCPError()
    } catch let error as PathError {
      throw MCPError.invalidParams(error.localizedDescription)
    }
  }
}
