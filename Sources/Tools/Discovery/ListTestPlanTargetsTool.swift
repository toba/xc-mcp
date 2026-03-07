import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

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
                    "format": .object([
                        "type": .string("string"),
                        "enum": .array([.string("text"), .string("json")]),
                        "description": .string(
                            "Output format: 'text' (default) or 'json'.",
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
        let format = arguments.getString("format") ?? "text"

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
                // Fall back to scheme testable references
                let projectFile = projectPath ?? workspacePath
                if let projectFile,
                   let targets = fetchSchemeTestableTargets(
                       scheme: scheme, projectPath: projectFile,
                   )
                {
                    if format == "json" {
                        return try formatSchemeTestableJSON(
                            targets: targets, scheme: scheme,
                        )
                    }
                    var output =
                        "Scheme '\(scheme)' (no test plan — using scheme test action):\n"
                    for target in targets {
                        let suffix = target.skipped ? " (skipped)" : ""
                        output += "  - \(target.name)\(suffix)\n"
                    }
                    return CallTool.Result(content: [.text(output)])
                }
                return CallTool.Result(
                    content: [
                        .text("No test plans found for scheme '\(scheme)'."),
                    ],
                )
            }

            if format == "json" {
                return try formatTestPlansJSON(
                    testPlanNames: testPlanNames, scheme: scheme, projectRoot: projectRoot,
                )
            }

            // Text format (existing behavior)
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

    private func formatTestPlansJSON(
        testPlanNames: [String], scheme: String, projectRoot: String,
    ) throws -> CallTool.Result {
        struct TestTargetResult: Encodable {
            let name: String
            let enabled: Bool
        }
        struct TestPlanResult: Encodable {
            let name: String
            let targets: [TestTargetResult]
        }
        struct Result: Encodable {
            let scheme: String
            let testPlans: [TestPlanResult]
        }

        let plans = testPlanNames.map { planName in
            let targets = findTestPlanTargets(planName: planName, searchRoot: projectRoot)
            return TestPlanResult(
                name: planName,
                targets: targets.map { TestTargetResult(name: $0.name, enabled: $0.enabled) },
            )
        }

        let result = Result(scheme: scheme, testPlans: plans)
        let json = try encodePrettyJSON(result)
        return CallTool.Result(content: [.text(json)])
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

    // MARK: - Scheme Testable Fallback

    struct SchemeTestTarget {
        let name: String
        let skipped: Bool
    }

    /// Parses the xcscheme's `<TestAction><Testables>` for testable target names.
    private func fetchSchemeTestableTargets(
        scheme: String, projectPath: String,
    ) -> [SchemeTestTarget]? {
        guard let schemePath = SchemePathResolver.findScheme(
            named: scheme, in: projectPath,
        )
        else { return nil }

        guard let xcscheme = try? XCScheme(path: Path(schemePath)) else {
            return nil
        }

        let testables = xcscheme.testAction?.testables ?? []
        if testables.isEmpty { return nil }

        return testables.map { testable in
            SchemeTestTarget(
                name: testable.buildableReference.blueprintName,
                skipped: testable.skipped,
            )
        }
    }

    private func formatSchemeTestableJSON(
        targets: [SchemeTestTarget], scheme: String,
    ) throws -> CallTool.Result {
        struct TargetEntry: Encodable {
            let name: String
            let skipped: Bool
        }
        struct Result: Encodable {
            let scheme: String
            let source: String
            let targets: [TargetEntry]
        }

        let result = Result(
            scheme: scheme,
            source: "scheme_test_action",
            targets: targets.map { TargetEntry(name: $0.name, skipped: $0.skipped) },
        )
        let json = try encodePrettyJSON(result)
        return CallTool.Result(content: [.text(json)])
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
