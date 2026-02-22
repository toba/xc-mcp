import Foundation
import MCP
import XCMCPCore

public struct XCStringsDeleteKeyTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "xcstrings_delete_key",
      description: "Delete a key entirely",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "file": .object([
            "type": .string("string"),
            "description": .string("Path to the xcstrings file"),
          ]),
          "key": .object([
            "type": .string("string"),
            "description": .string("The key to delete"),
          ]),
        ]),
        "required": .array([.string("file"), .string("key")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let filePath = try arguments.getRequiredString("file")
    let key = try arguments.getRequiredString("key")

    do {
      let resolvedPath = try pathUtility.resolvePath(from: filePath)
      let parser = XCStringsParser(path: resolvedPath)
      try await parser.deleteKey(key)

      return CallTool.Result(content: [.text("Key deleted successfully")])
    } catch let error as XCStringsError {
      throw error.toMCPError()
    } catch let error as PathError {
      throw MCPError.invalidParams(error.localizedDescription)
    }
  }
}
