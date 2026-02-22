import Foundation
import MCP
import XCMCPCore

public struct XCStringsBatchUpdateTranslationsTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "xcstrings_batch_update_translations",
      description:
        "Update translations for multiple keys at once. Each entry specifies a key and its language-value pairs to update.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "file": .object([
            "type": .string("string"),
            "description": .string("Path to the xcstrings file"),
          ]),
          "entries": .object([
            "type": .string("array"),
            "items": .object([
              "type": .string("object"),
              "properties": .object([
                "key": .object([
                  "type": .string("string"),
                  "description": .string("The localization key"),
                ]),
                "translations": .object([
                  "type": .string("object"),
                  "description": .string(
                    "Object mapping language codes to updated translation values",
                  ),
                ]),
              ]),
              "required": .array([.string("key"), .string("translations")]),
            ]),
            "description": .string(
              "Array of entries, each with a key and translations object",
            ),
          ]),
        ]),
        "required": .array([.string("file"), .string("entries")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let filePath = try arguments.getRequiredString("file")
    let entries = try arguments.parseBatchTranslationEntries()

    if entries.isEmpty {
      throw MCPError.invalidParams("entries array is required and cannot be empty")
    }

    do {
      let resolvedPath = try pathUtility.resolvePath(from: filePath)
      let parser = XCStringsParser(path: resolvedPath)
      let result = try await parser.updateTranslationsBatch(entries: entries)

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      let json = String(data: data, encoding: .utf8) ?? "{}"

      return CallTool.Result(content: [.text(json)])
    } catch let error as XCStringsError {
      throw error.toMCPError()
    } catch let error as PathError {
      throw MCPError.invalidParams(error.localizedDescription)
    }
  }
}
