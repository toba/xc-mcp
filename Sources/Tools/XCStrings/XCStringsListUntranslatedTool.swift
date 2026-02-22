import MCP
import XCMCPCore

public struct XCStringsListUntranslatedTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_list_untranslated",
            description: "List untranslated keys for a specific language",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Language code to check"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("language")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let language = try arguments.getRequiredString("language")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            let untranslated = try await parser.listUntranslated(for: language)

            let json = try encodePrettyJSON(untranslated, fallback: "[]")

            return CallTool.Result(content: [.text(json)])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
