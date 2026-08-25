import MCP
import XCMCPCore
import Foundation

public struct ListSchemesTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "list_schemes",
            description: "List all schemes available in an Xcode project or workspace.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(
                    [
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
                        "format": .object([
                            "type": .string("string"),
                            "enum": .array([.string("text"), .string("json")]),
                            "description": .string("Output format: 'text' (default) or 'json'."),
                        ]),
                    ].merging([String: Value].timeoutSchemaProperty(
                        defaultSeconds: 300, subject: "query"),
                    ) { _, new in new }
                        .merging([String: Value].queryOutputTimeoutSchemaProperty) { _, new in new }
                ),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let format = arguments.getString("format") ?? "text"
        let timeout = arguments.resolveTimeout(default: XcodebuildRunner.defaultTimeout)

        do {
            let result = try await xcodebuildRunner.listSchemes(
                projectPath: projectPath,
                workspacePath: workspacePath,
                timeout: timeout,
                outputTimeout: arguments.resolveOutputTimeout(
                    default: XcodebuildRunner.outputTimeout,
                ),
            )

            if result.succeeded {
                let output: String
                output = format == "json"
                    ? formatSchemesJSON(from: result.stdout)
                    : parseSchemeList(from: result.stdout)
                return CallTool.Result.text(output)
            } else {
                throw MCPError.internalError("Failed to list schemes: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    private func formatSchemesJSON(from json: String) -> String {
        let data = Data(json.utf8)
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
              let outputData = try? JSONSerialization.data(
                  withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys],
              ),
              let outputString = String(data: outputData, encoding: .utf8) else { return json }
        return outputString
    }

    /// The `xcodebuild -list -json` payload.
    ///
    /// A workspace payload carries the `workspace` key and a project payload the `project` key.
    private struct SchemeList: Decodable {
        /// The container the payload describes. A workspace names no target or configuration.
        struct Container: Decodable {
            let name: String?
            let schemes: [String]?
            let targets: [String]?
            let configurations: [String]?
        }

        let workspace: Container?
        let project: Container?
    }

    private func parseSchemeList(from json: String) -> String {
        guard let parsed = try? JSONDecoder().decode(SchemeList.self, from: Data(json.utf8)) else {
            // If not JSON, return raw output
            return json
        }

        var output = ""

        if let workspace = parsed.workspace {
            if let name = workspace.name { output += "Workspace: \(name)\n\n" }

            if let schemes = workspace.schemes {
                output += "Schemes (\(schemes.count)):\n"
                for scheme in schemes.sorted() { output += "  - \(scheme)\n" }
            }
        }

        if let project = parsed.project {
            if let name = project.name { output += "Project: \(name)\n\n" }

            if let schemes = project.schemes {
                output += "Schemes (\(schemes.count)):\n"
                for scheme in schemes.sorted() { output += "  - \(scheme)\n" }
            }

            if let targets = project.targets {
                output += "\nTargets (\(targets.count)):\n"
                for target in targets.sorted() { output += "  - \(target)\n" }
            }

            if let configurations = project.configurations {
                output += "\nConfigurations (\(configurations.count)):\n"
                for config in configurations { output += "  - \(config)\n" }
            }
        }

        return output.isEmpty ? json : output
    }
}
