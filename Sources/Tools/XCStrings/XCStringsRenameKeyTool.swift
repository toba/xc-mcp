import MCP
import XCMCPCore
import Foundation

public struct XCStringsRenameKeyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let oldKey = try arguments.getRequiredString("oldKey")
        let newKey = try arguments.getRequiredString("newKey")

        return try await pathUtility.withParser(at: filePath) { parser, _ in
            try await parser.renameKey(from: oldKey, to: newKey)

            return CallTool.Result.text("Key renamed from '\(oldKey)' to '\(newKey)' successfully")
        }
    }
}
