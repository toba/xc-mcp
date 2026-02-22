import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct RemoveTestPlanFromSchemeTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "remove_test_plan_from_scheme",
      description: "Remove a test plan reference from a scheme's TestAction",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "project_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to the .xcodeproj file (relative to current directory)",
            ),
          ]),
          "scheme_name": .object([
            "type": .string("string"),
            "description": .string("Name of the existing scheme"),
          ]),
          "test_plan_path": .object([
            "type": .string("string"),
            "description": .string("Path to the .xctestplan file to remove"),
          ]),
        ]),
        "required": .array([
          .string("project_path"), .string("scheme_name"), .string("test_plan_path"),
        ]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) throws -> CallTool.Result {
    guard case .string(let projectPath) = arguments["project_path"],
      case .string(let schemeName) = arguments["scheme_name"],
      case .string(let testPlanPath) = arguments["test_plan_path"]
    else {
      throw MCPError.invalidParams(
        "project_path, scheme_name, and test_plan_path are required",
      )
    }

    let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
    let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)

    guard
      let schemePath = SchemePathResolver.findScheme(
        named: schemeName, in: resolvedProjectPath,
      )
    else {
      return CallTool.Result(
        content: [
          .text("Scheme '\(schemeName)' not found in project")
        ],
      )
    }

    do {
      let scheme = try XCScheme(pathString: schemePath)

      let reference = SchemePathResolver.containerReference(
        for: resolvedTestPlanPath, relativeTo: resolvedProjectPath,
      )

      guard let testAction = scheme.testAction,
        let plans = testAction.testPlans,
        plans.contains(where: { $0.reference == reference })
      else {
        return CallTool.Result(
          content: [
            .text(
              "Test plan is not referenced in scheme '\(schemeName)'",
            )
          ],
        )
      }

      let filtered = plans.filter { $0.reference != reference }
      testAction.testPlans = filtered.isEmpty ? nil : filtered

      try scheme.write(path: Path(schemePath), override: true)

      return CallTool.Result(
        content: [
          .text(
            "Removed test plan from scheme '\(schemeName)'",
          )
        ],
      )
    } catch {
      throw MCPError.internalError(
        "Failed to remove test plan from scheme: \(error.localizedDescription)",
      )
    }
  }
}
