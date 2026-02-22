import MCP
import XCMCPCore
import Foundation

public struct XCStringsAddTranslationTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_add_translation",
            description: "Add a translation for a key",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to add translation for"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Language code for the translation"),
                    ]),
                    "value": .object([
                        "type": .string("string"),
                        "description": .string("Translation value"),
                    ]),
                ]),
                "required": .array([
                    .string("file"), .string("key"), .string("language"), .string("value"),
                ]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")
        let language = try arguments.getRequiredString("language")
        let value = try arguments.getRequiredString("value")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            try await parser.addTranslation(key: key, language: language, value: value)

            return CallTool.Result(content: [.text("Translation added successfully")])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
