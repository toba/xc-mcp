import Foundation
import MCP

public struct ListSchemesTool: Sendable {
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
            name: "list_schemes",
            description:
                "List all schemes available in an Xcode project or workspace.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified."),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments)

        do {
            let result = try await xcodebuildRunner.listSchemes(
                projectPath: projectPath,
                workspacePath: workspacePath
            )

            if result.succeeded {
                let parsed = try parseSchemeList(from: result.stdout)
                return CallTool.Result(content: [.text(parsed)])
            } else {
                throw MCPError.internalError(
                    "Failed to list schemes: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to list schemes: \(error.localizedDescription)")
        }
    }

    private func parseSchemeList(from json: String) -> String {
        guard let data = json.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // If not JSON, return raw output
            return json
        }

        var output = ""

        // Handle workspace format
        if let workspace = parsed["workspace"] as? [String: Any] {
            if let name = workspace["name"] as? String {
                output += "Workspace: \(name)\n\n"
            }

            if let schemes = workspace["schemes"] as? [String] {
                output += "Schemes (\(schemes.count)):\n"
                for scheme in schemes.sorted() {
                    output += "  - \(scheme)\n"
                }
            }
        }

        // Handle project format
        if let project = parsed["project"] as? [String: Any] {
            if let name = project["name"] as? String {
                output += "Project: \(name)\n\n"
            }

            if let schemes = project["schemes"] as? [String] {
                output += "Schemes (\(schemes.count)):\n"
                for scheme in schemes.sorted() {
                    output += "  - \(scheme)\n"
                }
            }

            if let targets = project["targets"] as? [String] {
                output += "\nTargets (\(targets.count)):\n"
                for target in targets.sorted() {
                    output += "  - \(target)\n"
                }
            }

            if let configurations = project["configurations"] as? [String] {
                output += "\nConfigurations (\(configurations.count)):\n"
                for config in configurations {
                    output += "  - \(config)\n"
                }
            }
        }

        if output.isEmpty {
            return json
        }

        return output
    }
}
