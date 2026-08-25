import MCP
import XCMCPCore

/// Installs the `tools/list` and `tools/call` handlers of `server` from ``ToolRegistry``
///
/// Every tool the registry marks as belonging to `serverSet` is built once, listed and dispatched.
/// A name no such tool answers to throws `methodNotFound` with a hint naming the server that does
/// carry it.
///
/// - Parameters:
///   - server: The MCP server to install the handlers on.
///   - serverSet: Which server this is. Selects the tools and names the caller in the hint.
///   - deps: The objects the tools are built from.
///   - gateByWorkflow: Whether a disabled workflow hides a tool from `tools/list` and refuses it in
///     `tools/call`. Only the monolith gates, because only it exposes `manage_workflows`.
public func installRegistryToolHandlers(
    on server: Server,
    as serverSet: ServerSet,
    deps: ToolDeps,
    gateByWorkflow: Bool = false,
) async {
    // Each descriptor allocates a nested schema tree, so both handlers read one prebuilt copy.
    let built = ToolRegistry.registrations(for: serverSet).map { ($0, $0.build(deps)) }
    let listed = built.map { ($0.0, $0.1.descriptor) }
    let runners = Dictionary(
        uniqueKeysWithValues: built.map { ($0.0.name, ($0.0, $0.1.run)) },
    )
    let workflows = deps.workflows

    await server.withMethodHandler(ListTools.self) { _ in
        guard gateByWorkflow else { return ListTools.Result(tools: listed.map { $0.1 }) }
        var tools: [Tool] = []
        tools.reserveCapacity(listed.count)
        for (registration, descriptor) in listed {
            if registration.ignoresWorkflowGate {
                tools.append(descriptor)
            } else if await workflows.isEnabled(registration.workflow) {
                tools.append(descriptor)
            }
        }
        return ListTools.Result(tools: tools)
    }

    await server.withMethodHandler(CallTool.self) { params in
        guard let (registration, run) = runners[params.name] else {
            throw MCPError.methodNotFound(
                ServerToolDirectory.unknownToolMessage(params.name, currentServer: serverSet),
            )
        }

        if gateByWorkflow, !registration.ignoresWorkflowGate {
            let enabled = await workflows.isEnabled(registration.workflow)
            if !enabled {
                throw MCPError.invalidRequest(
                    "Tool '\(params.name)' is disabled. Its workflow '\(registration.workflow.rawValue)' is currently disabled. Use manage_workflows to re-enable it.",
                )
            }
        }

        return try await run(
            ToolCall(
                arguments: params.arguments ?? [:],
                progressToken: params._meta?.progressToken,
                notify: { try await server.notify($0) },
            ),
        )
    }
}
