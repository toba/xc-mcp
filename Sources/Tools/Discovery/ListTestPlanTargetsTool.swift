import Foundation
import MCP
import XCMCPCore

public struct ListTestPlanTargetsTool: Sendable {
  private let xcodebuildRunner: XcodebuildRunner
  private let sessionManager: SessionManager

  public init(
    xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
    sessionManager: SessionManager,
  ) {
    self.xcodebuildRunner = xcodebuildRunner
    self.sessionManager = sessionManager
  }

  public func tool() -> Tool {
    Tool(
      name: "list_test_plan_targets",
      description:
        "List test plans and their test targets for a scheme. Returns target names usable with only_testing.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "project_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to the .xcodeproj file. Uses session default if not specified.",
            ),
          ]),
          "workspace_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to the .xcworkspace file. Uses session default if not specified.",
            ),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string(
              "The scheme to query for test plans. Uses session default if not specified.",
            ),
          ]),
        ]),
        "required": .array([]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
      from: arguments,
    )
    let scheme = try await sessionManager.resolveScheme(from: arguments)

    // Determine the project root directory for searching .xctestplan files
    let projectRoot: String
    if let workspacePath {
      let parent = URL(fileURLWithPath: workspacePath).deletingLastPathComponent().path
      projectRoot = parent.isEmpty ? "." : parent
    } else if let projectPath {
      let parent = URL(fileURLWithPath: projectPath).deletingLastPathComponent().path
      projectRoot = parent.isEmpty ? "." : parent
    } else {
      throw MCPError.invalidParams(
        "Either project_path or workspace_path is required",
      )
    }

    do {
      // Get test plan names from xcodebuild
      let testPlanNames = try await fetchTestPlanNames(
        projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
      )

      if testPlanNames.isEmpty {
        return CallTool.Result(
          content: [
            .text("No test plans found for scheme '\(scheme)'.")
          ],
        )
      }

      // Parse each .xctestplan file to extract test targets
      var output = "Test plans for scheme '\(scheme)':\n"
      for planName in testPlanNames {
        output += "\n  \(planName):\n"
        let targets = findTestPlanTargets(
          planName: planName, searchRoot: projectRoot,
        )
        if targets.isEmpty {
          output += "    (no targets found — .xctestplan file may be missing)\n"
        } else {
          for target in targets {
            let suffix = target.enabled ? "" : " (disabled)"
            output += "    - \(target.name)\(suffix)\n"
          }
        }
      }

      return CallTool.Result(content: [.text(output)])
    } catch {
      throw error.asMCPError()
    }
  }

  /// Runs `xcodebuild -showTestPlans` to get test plan names for a scheme.
  private func fetchTestPlanNames(
    projectPath: String?, workspacePath: String?, scheme: String,
  ) async throws -> [String] {
    var args: [String] = []

    if let workspacePath {
      args += ["-workspace", workspacePath]
    } else if let projectPath {
      args += ["-project", projectPath]
    }

    args += ["-scheme", scheme, "-showTestPlans", "-json"]

    let result = try await xcodebuildRunner.run(arguments: args)

    guard result.succeeded else {
      throw MCPError.internalError(
        "Failed to get test plans for scheme '\(scheme)': \(result.errorOutput)",
      )
    }

    // Parse JSON output to extract test plan names
    guard let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let testPlans = json["testPlans"] as? [[String: Any]]
    else {
      return []
    }

    return testPlans.compactMap { $0["name"] as? String }
  }

  /// Finds and parses a `.xctestplan` file to extract test target names and enabled status.
  package func findTestPlanTargets(planName: String, searchRoot: String) -> [(
    name: String, enabled: Bool,
  )] {
    let planFileName = "\(planName).xctestplan"
    let files = TestPlanFile.findFiles(under: searchRoot)
    guard
      let match = files.first(where: {
        URL(fileURLWithPath: $0.path).lastPathComponent == planFileName
      })
    else {
      return []
    }
    return TestPlanFile.targetEntries(from: match.json)
  }
}
