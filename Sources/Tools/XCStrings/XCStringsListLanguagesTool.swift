import Foundation
import MCP
import XCMCPCore

public struct XCStringsListLanguagesTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "xcstrings_list_languages",
      description: "List all languages in the xcstrings file",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "file": .object([
            "type": .string("string"),
            "description": .string("Path to the xcstrings file"),
          ])
        ]),
        "required": .array([.string("file")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let filePath = try arguments.getRequiredString("file")

    do {
      let resolvedPath = try pathUtility.resolvePath(from: filePath)
      let parser = XCStringsParser(path: resolvedPath)
      let languages = try await parser.listLanguages()

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(languages)
      let json = String(data: data, encoding: .utf8) ?? "[]"

      return CallTool.Result(content: [.text(json)])
    } catch let error as XCStringsError {
      throw error.toMCPError()
    } catch let error as PathError {
      throw MCPError.invalidParams(error.localizedDescription)
    }
  }
}
