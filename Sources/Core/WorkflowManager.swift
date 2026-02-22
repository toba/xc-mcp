/// Workflow categories for grouping MCP tools.
///
/// Each workflow represents a logical group of tools that can be
/// enabled or disabled together to reduce the tool surface area.
public enum Workflow: String, CaseIterable, Sendable {
  case project
  case session
  case simulator
  case device
  case macos
  case discovery
  case logging
  case debug
  case uiAutomation
  case interact
  case swiftPackage
  case instruments
  case utility
}

/// Manages which tool workflows are enabled or disabled.
///
/// All workflows are enabled by default. Disabling a workflow hides
/// its tools from `tools/list` and blocks execution in `tools/call`.
public actor WorkflowManager {
  private var disabledWorkflows: Set<Workflow> = []

  public init() {}

  public func enable(_ workflow: Workflow) {
    disabledWorkflows.remove(workflow)
  }

  public func disable(_ workflow: Workflow) {
    disabledWorkflows.insert(workflow)
  }

  public func isEnabled(_ workflow: Workflow) -> Bool {
    !disabledWorkflows.contains(workflow)
  }

  public func enabledList() -> [Workflow] {
    Workflow.allCases.filter { !disabledWorkflows.contains($0) }
  }

  public func disabledList() -> [Workflow] {
    Workflow.allCases.filter { disabledWorkflows.contains($0) }
  }

  public func reset() {
    disabledWorkflows.removeAll()
  }
}
