import Foundation
import MCP
import XCMCPCore

public struct XCStringsUpdateTranslationsTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "xcstrings_update_translations",
      description: "Update translations for multiple languages at once",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "file": .object([
            "type": .string("string"),
            "description": .string("Path to the xcstrings file"),
          ]),
          "key": .object([
            "type": .string("string"),
            "description": .string("The key to update translations for"),
          ]),
          "translations": .object([
            "type": .string("object"),
            "description": .string(
              "Object mapping language codes to translation values, e.g. {\"ja\": \"...\", \"en\": \"...\"}",
            ),
          ]),
        ]),
        "required": .array([.string("file"), .string("key"), .string("translations")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let filePath = try arguments.getRequiredString("file")
    let key = try arguments.getRequiredString("key")

    guard case .object(let translationsValue) = arguments["translations"] else {
      throw MCPError.invalidParams("translations object is required")
    }

    var translations: [String: String] = [:]
    for (lang, value) in translationsValue {
      if case .string(let stringValue) = value {
        translations[lang] = stringValue
      }
    }

    if translations.isEmpty {
      throw MCPError.invalidParams("translations object cannot be empty")
    }

    do {
      let resolvedPath = try pathUtility.resolvePath(from: filePath)
      let parser = XCStringsParser(path: resolvedPath)
      try await parser.updateTranslations(key: key, translations: translations)

      return CallTool.Result(
        content: [
          .text("Translations updated successfully for \(translations.count) languages")
        ],
      )
    } catch let error as XCStringsError {
      throw error.toMCPError()
    } catch let error as PathError {
      throw MCPError.invalidParams(error.localizedDescription)
    }
  }
}
