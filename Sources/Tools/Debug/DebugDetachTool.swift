import Foundation
import MCP

public struct DebugDetachTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_detach",
            description:
                "Detach the LLDB debugger from a process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to detach from."),
                    ]),
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID to detach from."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid: Int32?

        if case let .int(value) = arguments["pid"] {
            pid = Int32(value)
        }

        if pid == nil, case let .string(bundleId) = arguments["bundle_id"] {
            pid = await LLDBSessionManager.shared.getSession(bundleId: bundleId)
            if pid != nil {
                await LLDBSessionManager.shared.removeSession(bundleId: bundleId)
            }
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either bundle_id (with active session) or pid is required")
        }

        do {
            let result = try await lldbRunner.detach(pid: targetPID)

            var message = "Detached from process \(targetPID)"
            if !result.output.isEmpty {
                message += "\n\n\(result.output)"
            }

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to detach: \(error.localizedDescription)")
        }
    }
}
