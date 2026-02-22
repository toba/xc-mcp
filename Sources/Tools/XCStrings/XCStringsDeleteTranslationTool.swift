import Foundation
import MCP
import XCMCPCore

public struct XCStringsDeleteTranslationTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_delete_translation",
            description: "Delete a specific translation for a key",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to delete translation from"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Language code to delete"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("key"), .string("language")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")
        let language = try arguments.getRequiredString("language")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            try await parser.deleteTranslation(key: key, language: language)

            return CallTool.Result(
                content: [.text("Translation for '\(language)' deleted successfully")]
            )
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
