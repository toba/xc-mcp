import Foundation
import XCMCPCore
import MCP

public struct ShowBuildSettingsTool: Sendable {
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
            name: "show_build_settings",
            description:
                "Show all build settings for a scheme. Returns detailed build settings including paths, identifiers, and compilation flags.",
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
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to get build settings for. Uses session default if not specified."
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                    "filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional filter to show only settings containing this string (case-insensitive)."
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
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let filter = arguments.getString("filter")?.lowercased()

        do {
            let result = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration
            )

            if result.succeeded {
                let parsed = formatBuildSettings(from: result.stdout, filter: filter)
                return CallTool.Result(content: [.text(parsed)])
            } else {
                throw MCPError.internalError(
                    "Failed to get build settings: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to get build settings: \(error.localizedDescription)")
        }
    }

    private func formatBuildSettings(from json: String, filter: String?) -> String {
        guard let data = json.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            // If not JSON, return raw output (possibly filtered)
            if let filter {
                let lines = json.components(separatedBy: .newlines)
                let filtered = lines.filter { $0.lowercased().contains(filter) }
                return filtered.joined(separator: "\n")
            }
            return json
        }

        var output = ""

        for targetSettings in parsed {
            guard let target = targetSettings["target"] as? String,
                let settings = targetSettings["buildSettings"] as? [String: Any]
            else {
                continue
            }

            output += "Target: \(target)\n"
            output += String(repeating: "=", count: 60) + "\n\n"

            // Sort settings by key
            let sortedKeys = settings.keys.sorted()

            for key in sortedKeys {
                guard let value = settings[key] else { continue }

                // Apply filter if specified
                if let filter {
                    let keyLower = key.lowercased()
                    let valueLower = String(describing: value).lowercased()
                    if !keyLower.contains(filter) && !valueLower.contains(filter) {
                        continue
                    }
                }

                let valueStr = String(describing: value)
                output += "\(key) = \(valueStr)\n"
            }

            output += "\n"
        }

        if output.isEmpty {
            if let filter {
                return "No build settings found matching filter '\(filter)'"
            }
            return "No build settings found"
        }

        return output
    }
}
