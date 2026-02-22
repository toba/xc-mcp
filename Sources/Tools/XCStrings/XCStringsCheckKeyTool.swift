import MCP
import XCMCPCore
import Foundation

public struct XCStringsCheckKeyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_check_key",
            description: "Check if a key exists in the xcstrings file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to check"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Optional specific language to check"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("key")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")
        let language = arguments.getString("language")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            let exists = try await parser.checkKey(key, language: language)

            return CallTool.Result(content: [.text(String(exists))])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
