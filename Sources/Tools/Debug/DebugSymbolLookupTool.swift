import MCP
import XCMCPCore
import Foundation

public struct DebugSymbolLookupTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_symbol_lookup",
            description:
            "Look up symbols, addresses, and types in a debugged process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the debugged process.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session).",
                        ),
                    ]),
                    "address": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Address to symbolicate (hex).",
                        ),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Symbol or function name regex to search for.",
                        ),
                    ]),
                    "type": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Type name to look up.",
                        ),
                    ]),
                    "verbose": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Verbose output. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = arguments.getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required",
            )
        }

        let address = arguments.getString("address")
        let name = arguments.getString("name")
        let typeName = arguments.getString("type")
        let verbose = arguments.getBool("verbose")

        if address == nil, name == nil, typeName == nil {
            throw MCPError.invalidParams(
                "At least one of 'address', 'name', or 'type' is required",
            )
        }

        do {
            let result = try await lldbRunner.symbolLookup(
                pid: targetPID,
                address: address,
                name: name,
                type: typeName,
                verbose: verbose,
            )

            let message = "Symbol lookup result:\n\n\(result.output)"
            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
