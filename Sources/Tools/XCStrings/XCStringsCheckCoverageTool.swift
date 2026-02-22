import MCP
import XCMCPCore

public struct XCStringsCheckCoverageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_check_coverage",
            description:
            "Check translation coverage for a specific key, showing which languages have translations and which are missing",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to check coverage for"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("key")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            let coverage = try await parser.checkCoverage(key)

            let json = try encodePrettyJSON(coverage)

            return CallTool.Result(content: [.text(json)])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
