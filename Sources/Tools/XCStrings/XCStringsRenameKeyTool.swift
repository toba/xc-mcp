import Foundation
import MCP
import XCMCPCore

public struct XCStringsRenameKeyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_rename_key",
            description: "Rename a key",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "oldKey": .object([
                        "type": .string("string"),
                        "description": .string("Current key name"),
                    ]),
                    "newKey": .object([
                        "type": .string("string"),
                        "description": .string("New key name"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("oldKey"), .string("newKey")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let oldKey = try arguments.getRequiredString("oldKey")
        let newKey = try arguments.getRequiredString("newKey")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            try await parser.renameKey(from: oldKey, to: newKey)

            return CallTool.Result(
                content: [.text("Key renamed from '\(oldKey)' to '\(newKey)' successfully")]
            )
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
