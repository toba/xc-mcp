import Foundation
import MCP
import XCMCPCore

public struct ListTestPlanTargetsTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager
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
                            "Path to the .xcodeproj file. Uses session default if not specified."
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified."
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to query for test plans. Uses session default if not specified."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)

        // Determine the project root directory for searching .xctestplan files
        let projectRoot: String
        if let workspacePath {
            let parent = (workspacePath as NSString).deletingLastPathComponent
            projectRoot = parent.isEmpty ? "." : parent
        } else if let projectPath {
            let parent = (projectPath as NSString).deletingLastPathComponent
            projectRoot = parent.isEmpty ? "." : parent
        } else {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required"
            )
        }

        do {
            // Get test plan names from xcodebuild
            let testPlanNames = try await fetchTestPlanNames(
                projectPath: projectPath, workspacePath: workspacePath, scheme: scheme
            )

            if testPlanNames.isEmpty {
                return CallTool.Result(
                    content: [
                        .text("No test plans found for scheme '\(scheme)'."),
                    ]
                )
            }

            // Parse each .xctestplan file to extract test targets
            var output = "Test plans for scheme '\(scheme)':\n"
            for planName in testPlanNames {
                output += "\n  \(planName):\n"
                let targets = findTestPlanTargets(
                    planName: planName, searchRoot: projectRoot
                )
                if targets.isEmpty {
                    output += "    (no targets found — .xctestplan file may be missing)\n"
                } else {
                    for target in targets {
                        output += "    - \(target)\n"
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
        projectPath: String?, workspacePath: String?, scheme: String
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
                "Failed to get test plans for scheme '\(scheme)': \(result.errorOutput)"
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

    /// Finds and parses a `.xctestplan` file to extract test target names.
    package func findTestPlanTargets(planName: String, searchRoot: String) -> [String] {
        let fm = FileManager.default
        let planFileName = "\(planName).xctestplan"

        // Search recursively for the .xctestplan file
        guard let enumerator = fm.enumerator(atPath: searchRoot) else {
            return []
        }

        var planPath: String?
        while let path = enumerator.nextObject() as? String {
            if (path as NSString).lastPathComponent == planFileName {
                planPath = (searchRoot as NSString).appendingPathComponent(path)
                break
            }
        }

        guard let planPath,
              let data = fm.contents(atPath: planPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let testTargets = json["testTargets"] as? [[String: Any]]
        else {
            return []
        }

        return testTargets.compactMap { entry -> String? in
            guard let target = entry["target"] as? [String: Any],
                  let name = target["name"] as? String
            else {
                return nil
            }
            return name
        }
    }
}
