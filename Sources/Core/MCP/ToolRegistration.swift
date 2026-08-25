import Foundation

/// The shared objects every tool is built from
///
/// A server creates one `ToolDeps` and passes it to ``ToolRegistration/build(_:)``. Each field is a
/// cheap value type or an actor reference, so a server that hosts a handful of tools pays nothing
/// for the fields it never reads.
public struct ToolDeps: Sendable {
    public let paths: PathUtility
    public let session: SessionManager
    public let workflows: WorkflowManager
    public let xcodebuild: XcodebuildRunner
    public let simctl: SimctlRunner
    public let devicectl: DeviceCtlRunner
    public let lldb: LLDBRunner
    public let swift: SwiftRunner
    public let xctrace: XctraceRunner
    public let interact: InteractRunner
    public let simulatorInput: SimulatorUIInput

    /// Tells the client that the visible tool list changed.
    ///
    /// Only `manage_workflows` sends this. A server whose tool list is fixed passes a closure that
    /// does nothing.
    public let notifyToolListChanged: @Sendable () async throws -> Void

    public init(
        basePath: String,
        sandboxEnabled: Bool = true,
        session: SessionManager = .init(),
        workflows: WorkflowManager = .init(),
        notifyToolListChanged: @escaping @Sendable () async throws -> Void = {},
    ) {
        paths = PathUtility(basePath: basePath, sandboxEnabled: sandboxEnabled)
        self.session = session
        self.workflows = workflows
        let simctl = SimctlRunner()
        xcodebuild = XcodebuildRunner()
        self.simctl = simctl
        devicectl = DeviceCtlRunner()
        lldb = LLDBRunner()
        swift = SwiftRunner()
        xctrace = XctraceRunner()
        interact = InteractRunner()
        simulatorInput = SimulatorUIInput(simctlRunner: simctl)
        self.notifyToolListChanged = notifyToolListChanged
    }
}

/// One `tools/call` request, reduced to what a tool runner needs
public struct ToolCall: Sendable {
    public let arguments: [String: Value]

    /// The token the client asked for progress on, or `nil` when it wants none.
    public let progressToken: ProgressToken?

    /// Sends one `notifications/progress` message to the client.
    public let notify: @Sendable (Message<ProgressNotification>) async throws -> Void

    public init(
        arguments: [String: Value],
        progressToken: ProgressToken?,
        notify: @escaping @Sendable (Message<ProgressNotification>) async throws -> Void,
    ) {
        self.arguments = arguments
        self.progressToken = progressToken
        self.notify = notify
    }

    /// Runs `body` under a progress reporter when the client supplied a progress token.
    ///
    /// The closure `body` receives the sink to feed process output into. Without a token the sink
    /// discards every chunk and no notification is sent, which is what a client that omitted
    /// `progressToken` expects.
    ///
    /// ```swift
    /// try await call.withProgress { onProgress in
    ///     try await tool.execute(arguments: call.arguments, onProgress: onProgress)
    /// }
    /// ```
    public func withProgress(
        _ body: @Sendable (@escaping @Sendable (String) -> Void) async throws -> CallTool.Result,
    ) async throws -> CallTool.Result {
        guard let progressToken else { return try await body { _ in } }
        let reporter = ProgressReporter(token: progressToken, notify: notify)
        return try await reporter.stream { try await body(reporter.onProgress) }
    }
}

/// One tool, declared once
///
/// ``name``, ``workflow`` and ``servers`` read without building anything, so the cross-server
/// directory indexes the registry without creating a single tool. ``build(_:)`` creates the tool
/// and returns its MCP descriptor together with the closure that runs it, which keeps the tool's
/// concrete type local to the registration.
///
/// ```swift
/// ToolRegistration("list_targets", .project, [.monolith, .project]) { deps in
///     let tool = ListTargetsTool(pathUtility: deps.paths)
///     return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
/// }
/// ```
public struct ToolRegistration: Sendable {
    /// Runs one tool call.
    public typealias Runner = @Sendable (ToolCall) async throws -> CallTool.Result

    /// The descriptor a server lists and the closure a server dispatches to.
    public typealias Built = (descriptor: Tool, run: Runner)

    /// The MCP tool name.
    public let name: String

    /// The workflow category the monolith gates this tool behind.
    public let workflow: Workflow

    /// Every server that exposes this tool.
    public let servers: ServerSet

    /// Whether the tool stays reachable while its workflow is disabled.
    ///
    /// Only `manage_workflows` sets this. Gating it would leave a client no way to re-enable the
    /// workflow it just turned off.
    public let ignoresWorkflowGate: Bool

    private let make: @Sendable (ToolDeps) -> Built

    public init(
        _ name: String,
        _ workflow: Workflow,
        _ servers: ServerSet,
        ignoresWorkflowGate: Bool = false,
        make: @escaping @Sendable (ToolDeps) -> Built,
    ) {
        self.name = name
        self.workflow = workflow
        self.servers = servers
        self.ignoresWorkflowGate = ignoresWorkflowGate
        self.make = make
    }

    /// Creates the tool against `deps`.
    public func build(_ deps: ToolDeps) -> Built { make(deps) }
}
