import MCP
import XCMCPCore
import Foundation

public struct XCStringsCreateFileTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_create_file",
            description: "Create a new xcstrings file with the specified source language",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path for the new xcstrings file"),
                    ]),
                    "sourceLanguage": .object([
                        "type": .string("string"),
                        "description": .string("Source language code (default: en)"),
                    ]),
                    "overwrite": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Overwrite existing file if it exists (default: false)",
                        ),
                    ]),
                ]),
                "required": .array([.string("file")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let sourceLanguage = arguments.getString("sourceLanguage") ?? "en"
        let overwrite = arguments.getBool("overwrite", default: false)

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            try XCStringsParser.createFile(
                at: resolvedPath, sourceLanguage: sourceLanguage, overwrite: overwrite,
            )

            return CallTool.Result(
                content: [
                    .text(
                        "Created xcstrings file at '\(resolvedPath)' with source language '\(sourceLanguage)'",
                    ),
                ],
            )
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
