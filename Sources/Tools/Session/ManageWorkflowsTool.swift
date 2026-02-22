import MCP
import XCMCPCore
import Foundation

public struct ManageWorkflowsTool: Sendable {
    private let workflowManager: WorkflowManager

    public init(workflowManager: WorkflowManager) {
        self.workflowManager = workflowManager
    }

    public func tool() -> Tool {
        Tool(
            name: "manage_workflows",
            description:
            "Enable or disable tool workflow categories to reduce the tool surface area. Disabled workflows hide their tools from discovery and block execution.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Action to perform: enable, disable, list, or reset.",
                        ),
                        "enum": .array([
                            .string("enable"), .string("disable"),
                            .string("list"), .string("reset"),
                        ]),
                    ]),
                    "workflows": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array(
                                Workflow.allCases.map { .string($0.rawValue) },
                            ),
                        ]),
                        "description": .string(
                            "Workflow names to enable or disable. Required for enable/disable actions. Valid values: \(Workflow.allCases.map(\.rawValue).joined(separator: ", "))",
                        ),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
        )
    }

    /// Executes the workflow management action.
    ///
    /// - Returns: A tuple of the result and whether the tool list changed.
    public func execute(arguments: [String: Value]) async throws -> (
        result: CallTool.Result, toolListChanged: Bool,
    ) {
        let action = try arguments.getRequiredString("action")
        let workflowNames = arguments.getStringArray("workflows")

        switch action {
            case "list":
                let enabled = await workflowManager.enabledList()
                let disabled = await workflowManager.disabledList()
                var message = "Workflow status:\n"
                message += "\nEnabled (\(enabled.count)):\n"
                message += enabled.map { "  \($0.rawValue)" }.joined(separator: "\n")
                if !disabled.isEmpty {
                    message += "\n\nDisabled (\(disabled.count)):\n"
                    message += disabled.map { "  \($0.rawValue)" }.joined(separator: "\n")
                }
                return (CallTool.Result(content: [.text(message)]), false)

            case "enable":
                guard !workflowNames.isEmpty else {
                    throw MCPError.invalidParams(
                        "workflows array is required for enable action",
                    )
                }
                var enabled: [String] = []
                for name in workflowNames {
                    guard let workflow = Workflow(rawValue: name) else {
                        throw MCPError.invalidParams(
                            "Unknown workflow '\(name)'. Valid: \(Workflow.allCases.map(\.rawValue).joined(separator: ", "))",
                        )
                    }
                    await workflowManager.enable(workflow)
                    enabled.append(name)
                }
                return (
                    CallTool.Result(
                        content: [.text("Enabled workflows: \(enabled.joined(separator: ", "))")],
                    ),
                    true,
                )

            case "disable":
                guard !workflowNames.isEmpty else {
                    throw MCPError.invalidParams(
                        "workflows array is required for disable action",
                    )
                }
                var disabled: [String] = []
                for name in workflowNames {
                    guard let workflow = Workflow(rawValue: name) else {
                        throw MCPError.invalidParams(
                            "Unknown workflow '\(name)'. Valid: \(Workflow.allCases.map(\.rawValue).joined(separator: ", "))",
                        )
                    }
                    await workflowManager.disable(workflow)
                    disabled.append(name)
                }
                return (
                    CallTool.Result(
                        content: [.text("Disabled workflows: \(disabled.joined(separator: ", "))")],
                    ),
                    true,
                )

            case "reset":
                await workflowManager.reset()
                return (
                    CallTool.Result(content: [.text("All workflows re-enabled.")]),
                    true,
                )

            default:
                throw MCPError.invalidParams(
                    "Unknown action '\(action)'. Use: enable, disable, list, or reset.",
                )
        }
    }
}
