import Foundation
import MCP
import XCMCPCore

public struct XCStringsGetKeyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_get_key",
            description: "Get translations for a specific key",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to get translations for"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Optional specific language to get"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("key")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")
        let language = arguments.getString("language")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            let translations = try await parser.getTranslation(key: key, language: language)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(translations)
            let json = String(data: data, encoding: .utf8) ?? "{}"

            return CallTool.Result(content: [.text(json)])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
