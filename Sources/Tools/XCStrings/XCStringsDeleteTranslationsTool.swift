import Foundation
import MCP
import XCMCPCore

public struct XCStringsDeleteTranslationsTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "xcstrings_delete_translations",
      description: "Delete translations for multiple languages at once",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "file": .object([
            "type": .string("string"),
            "description": .string("Path to the xcstrings file"),
          ]),
          "key": .object([
            "type": .string("string"),
            "description": .string("The key to delete translations from"),
          ]),
          "languages": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(
              "Array of language codes to delete, e.g. [\"ja\", \"en\", \"fr\"]",
            ),
          ]),
        ]),
        "required": .array([.string("file"), .string("key"), .string("languages")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let filePath = try arguments.getRequiredString("file")
    let key = try arguments.getRequiredString("key")
    let languages = arguments.getStringArray("languages")

    if languages.isEmpty {
      throw MCPError.invalidParams("languages array is required and cannot be empty")
    }

    do {
      let resolvedPath = try pathUtility.resolvePath(from: filePath)
      let parser = XCStringsParser(path: resolvedPath)
      try await parser.deleteTranslations(key: key, languages: languages)

      return CallTool.Result(
        content: [
          .text("Translations deleted successfully for \(languages.count) languages")
        ],
      )
    } catch let error as XCStringsError {
      throw error.toMCPError()
    } catch let error as PathError {
      throw MCPError.invalidParams(error.localizedDescription)
    }
  }
}
