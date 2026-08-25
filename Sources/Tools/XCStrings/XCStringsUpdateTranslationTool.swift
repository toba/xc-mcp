import MCP
import XCMCPCore
import Foundation

public struct XCStringsUpdateTranslationTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_update_translation",
            description: "Update a translation for a key",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to update translation for"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Language code for the translation"),
                    ]),
                    "value": .object([
                        "type": .string("string"),
                        "description": .string("New translation value"),
                    ]),
                ]),
                "required": .array([
                    .string("file"), .string("key"), .string("language"), .string("value"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")
        let language = try arguments.getRequiredString("language")
        let value = try arguments.getRequiredString("value")

        return try await pathUtility.withParser(at: filePath) { parser, _ in
            try await parser.updateTranslation(key: key, language: language, value: value)

            return CallTool.Result.text("Translation updated successfully")
        }
    }
}
