import MCP
import XCMCPCore
import Foundation

public struct ShowBuildSettingsTool: Sendable {
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
            name: "show_build_settings",
            description:
                "Show build settings for a scheme. Supports filtering and field selection.",
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
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let filter = arguments.getString("filter")?.lowercased()
        let fieldSet = Set(arguments.getStringArray("fields"))
        let format = arguments.getString("format") ?? "text"
        let timeout = arguments.resolveTimeout(default: XcodebuildRunner.defaultTimeout)

        do {
            let result = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                timeout: timeout,
                outputTimeout: arguments.resolveOutputTimeout(
                    default: XcodebuildRunner.outputTimeout,
                ),
            )

            if result.succeeded {
                let output: String
                output = format == "json"
                    ? formatBuildSettingsJSON(from: result.stdout, fields: fieldSet, filter: filter)
                    : formatBuildSettings(from: result.stdout, fields: fieldSet, filter: filter)
                return CallTool.Result.text(output)
            } else {
                throw MCPError.internalError("Failed to get build settings: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Keeps the settings a `fields` list names, or the ones a `filter` matches.
    ///
    /// An empty `fields` list falls through to `filter`. Neither one keeps every setting.
    private static func select(
        _ settings: [String: String],
        fields: Set<String>,
        filter: String?,
    ) -> [String: String] {
        if !fields.isEmpty { return settings.filter { fields.contains($0.key) } }
        guard let filter else { return settings }
        return settings.filter { key, value in
            key.lowercased().contains(filter) || value.lowercased().contains(filter)
        }
    }

    private func formatBuildSettings(
        from json: String,
        fields: Set<String>,
        filter: String?,
    ) -> String {
        guard let entries = BuildSettingExtractor.decodeEntries(json) else {
            // If not JSON, return raw output (possibly filtered)
            if let filter {
                let lines = json.components(separatedBy: .newlines)
                let filtered = lines.filter { $0.lowercased().contains(filter) }
                return filtered.joined(separator: "\n")
            }
            return json
        }

        var output = ""

        for entry in entries {
            guard let target = entry.target else { continue }

            output += "Target: \(target)\n"
            output += String(repeating: "=", count: 60) + "\n\n"

            let selected = Self.select(entry.buildSettings, fields: fields, filter: filter)
            for key in selected.keys.sorted() { output += "\(key) = \(selected[key] ?? "")\n" }

            output += "\n"
        }

        if output.isEmpty {
            if !fields.isEmpty {
                return
                    "No build settings found for fields: \(fields.sorted().joined(separator: ", "))"
            }
            if let filter { return "No build settings found matching filter '\(filter)'" }
            return "No build settings found"
        }

        return output
    }

    private func formatBuildSettingsJSON(
        from json: String,
        fields: Set<String>,
        filter: String?,
    ) -> String {
        guard let entries = BuildSettingExtractor.decodeEntries(json) else { return json }

        let filtered = entries.compactMap { entry -> BuildSettingsEntry? in
            guard entry.target != nil else { return nil }
            return BuildSettingsEntry(
                target: entry.target,
                buildSettings: Self.select(entry.buildSettings, fields: fields, filter: filter),
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let outputData = try? encoder.encode(filtered),
              let outputString = String(data: outputData, encoding: .utf8) else { return json }

        return outputString
    }
}
