import MCP
import XCMCPCore
import Foundation

public struct DebugViewHierarchyTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = .init()) { self.lldbRunner = lldbRunner }

    public func tool() -> Tool {
        .init(
            name: "debug_view_hierarchy",
            description:
                "Dump the UI view hierarchy of a running app.",
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
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Platform: 'ios' (default) or 'macos'.",
                        ),
                    ]),
                    "address": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Specific view address to inspect. Omit for root view hierarchy.",
                        ),
                    ]),
                    "constraints": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Show Auto Layout constraints for the view. Defaults to false.",
                        ),
                    ]),
                    "max_depth": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Limit recursive descent to N levels via a bounded NSView/UIView walk that prints class, address, and frame per node. Use to keep SwiftUI-heavy hierarchies under the LLDB expression timeout (defaults to unbounded `_subtreeDescription`/`recursiveDescription`).",
                        ),
                    ]),
                    "class_filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only print nodes whose class name contains this substring (e.g. `NSHostingView`). Triggers the bounded walk; children are still descended so a matching ancestor surfaces its matching descendants.",
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Override the per-expression timeout in seconds (default 15). Raise for large hierarchies; the per-command read timeout is raised to match.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
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

        let platform = arguments.getString("platform") ?? "ios"
        let address = arguments.getString("address")
        let constraints = arguments.getBool("constraints")
        let maxDepth = arguments.getInt("max_depth")
        let classFilter = arguments.getString("class_filter")
        let timeoutSeconds = arguments.getDouble("timeout")

        do {
            // Expression evaluation fails on crashed processes (ObjC runtime not loaded)
            if let warning = await lldbRunner.crashWarning(pid: targetPID) {
                return CallTool.Result(
                    content: [.text(text: warning, annotations: nil, _meta: nil)],
                    isError: true,
                )
            }

            let result = try await lldbRunner.viewHierarchy(
                pid: targetPID,
                platform: platform,
                address: address,
                constraints: constraints,
                maxDepth: maxDepth,
                classFilter: classFilter,
                timeoutSeconds: timeoutSeconds,
            )

            let message = "View hierarchy:\n\n\(result.output)"
            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }
}
