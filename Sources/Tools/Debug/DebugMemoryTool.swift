import Foundation
import MCP
import XCMCPCore

public struct DebugMemoryTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_memory",
            description:
                "Read memory at an address in a debugged process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the debugged process."),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session)."),
                    ]),
                    "address": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Memory address to read (hex, e.g., '0x7fff5fbff8c0')."),
                    ]),
                    "count": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of items to read. Defaults to 16."),
                    ]),
                    "format": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Output format: 'hex', 'bytes', 'ascii', or 'instruction'. Defaults to 'hex'."
                        ),
                    ]),
                    "size": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Item size in bytes: 1, 2, 4, or 8. Defaults to 4."),
                    ]),
                ]),
                "required": .array([.string("address")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid: Int32?
        if case let .int(value) = arguments["pid"] {
            pid = Int32(value)
        }

        if pid == nil, case let .string(bundleId) = arguments["bundle_id"] {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required"
            )
        }

        let address = try arguments.getRequiredString("address")
        let count = arguments.getInt("count") ?? 16
        let format = arguments.getString("format") ?? "hex"
        let size = arguments.getInt("size") ?? 4

        do {
            let result = try await lldbRunner.readMemory(
                pid: targetPID,
                address: address,
                count: count,
                format: format,
                size: size
            )

            let message = "Memory at \(address):\n\n\(result.output)"
            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
