import MCP
import XCMCPCore
import Foundation

public struct ShowBuildSettingsTool: Sendable {
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
            name: "show_build_settings",
            description:
            "Show build settings for a scheme. Supports filtering and field selection.",
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
                            "The scheme to get build settings for. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug.",
                        ),
                    ]),
                    "filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional filter to show only settings containing this string (case-insensitive).",
                        ),
                    ]),
                    "fields": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Exact build setting key names to return (e.g., [\"PRODUCT_NAME\", \"SWIFT_VERSION\"]). Takes precedence over filter.",
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
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let filter = arguments.getString("filter")?.lowercased()
        let fieldSet = Set(arguments.getStringArray("fields"))
        let format = arguments.getString("format") ?? "text"

        do {
            let result = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            if result.succeeded {
                let output: String
                if format == "json" {
                    output = formatBuildSettingsJSON(
                        from: result.stdout,
                        fields: fieldSet,
                        filter: filter,
                    )
                } else {
                    output = formatBuildSettings(
                        from: result.stdout,
                        fields: fieldSet,
                        filter: filter,
                    )
                }
                return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
            } else {
                throw MCPError.internalError(
                    "Failed to get build settings: \(result.errorOutput)",
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }

    private func formatBuildSettings(
        from json: String,
        fields: Set<String>,
        filter: String?,
    ) -> String {
        let data = Data(json.utf8)
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
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

                // Fields takes precedence over filter
                if !fields.isEmpty {
                    if !fields.contains(key) { continue }
                } else if let filter {
                    let keyLower = key.lowercased()
                    let valueLower = String(describing: value).lowercased()
                    if !keyLower.contains(filter), !valueLower.contains(filter) {
                        continue
                    }
                }

                let valueStr = String(describing: value)
                output += "\(key) = \(valueStr)\n"
            }

            output += "\n"
        }

        if output.isEmpty {
            if !fields.isEmpty {
                return "No build settings found for fields: \(fields.sorted().joined(separator: ", "))"
            }
            if let filter {
                return "No build settings found matching filter '\(filter)'"
            }
            return "No build settings found"
        }

        return output
    }

    private func formatBuildSettingsJSON(
        from json: String,
        fields: Set<String>,
        filter: String?,
    ) -> String {
        let data = Data(json.utf8)
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return json
        }

        // Apply fields/filter to each target's build settings
        let filtered: [[String: Any]] = parsed.compactMap { targetSettings in
            guard let target = targetSettings["target"] as? String,
                  let settings = targetSettings["buildSettings"] as? [String: Any]
            else {
                return nil
            }

            let filteredSettings: [String: Any]
            if !fields.isEmpty {
                filteredSettings = settings.filter { fields.contains($0.key) }
            } else if let filter {
                filteredSettings = settings.filter { key, value in
                    key.lowercased().contains(filter)
                        || String(describing: value).lowercased().contains(filter)
                }
            } else {
                filteredSettings = settings
            }

            return [
                "target": target,
                "buildSettings": filteredSettings,
            ]
        }

        guard
            let outputData = try? JSONSerialization.data(
                withJSONObject: filtered, options: [.prettyPrinted, .sortedKeys],
            ), let outputString = String(data: outputData, encoding: .utf8)
        else {
            return json
        }

        return outputString
    }
}
