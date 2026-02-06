import Foundation
import MCP
import XCMCPCore

public struct XCStringsBatchCheckKeysTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_batch_check_keys",
            description: "Check if multiple keys exist in an xcstrings file in one call",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "keys": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Array of keys to check"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional language to check translations for"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("keys")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let keys = arguments.getStringArray("keys")
        if keys.isEmpty {
            throw MCPError.invalidParams("keys array is required and cannot be empty")
        }
        let language = arguments.getString("language")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            let results = try await parser.checkKeys(keys, language: language)

            let batchResult = BatchCheckKeysResult(results: results)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(batchResult)
            let json = String(data: data, encoding: .utf8) ?? "{}"

            return CallTool.Result(content: [.text(json)])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
