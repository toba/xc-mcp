import MCP
import XCMCPCore
import Foundation

public struct ListTestPlansTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_test_plans",
            description:
            "List all .xctestplan files in the project directory with their target lists",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (search root is the parent directory)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let searchRoot = URL(fileURLWithPath: resolvedProjectPath)
            .deletingLastPathComponent().path

        let testPlans = TestPlanFile.findFiles(under: searchRoot)

        if testPlans.isEmpty {
            return CallTool.Result(
                content: [.text("No .xctestplan files found under \(searchRoot)")],
            )
        }

        var lines = ["Found \(testPlans.count) test plan(s):\n"]
        for plan in testPlans {
            lines.append("  \(plan.path)")

            let targets = TestPlanFile.targetNames(from: plan.json)
            if targets.isEmpty {
                lines.append("    Targets: (none)")
            } else {
                lines.append("    Targets: \(targets.joined(separator: ", "))")
            }

            if let configs = plan.json["configurations"] as? [[String: Any]] {
                let configNames = configs.compactMap { $0["name"] as? String }
                if !configNames.isEmpty {
                    lines.append(
                        "    Configurations: \(configNames.joined(separator: ", "))",
                    )
                }
            }

            lines.append("")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
