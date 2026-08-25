import MCP
import XCMCPCore

public struct ManageURLTypeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "manage_url_type",
            description:
                "Add, update, or remove a URL type (CFBundleURLTypes entry) in a target's Info.plist. URL types define custom URL schemes the app can handle.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target"),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Action to perform: add, update, or remove"),
                        "enum": .array([.string("add"), .string("update"), .string("remove")]),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "URL type identifier (CFBundleURLName). Used as the primary key for lookup.",
                        ),
                    ]),
                    "url_schemes": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "URL schemes for CFBundleURLSchemes (e.g. [\"myapp\", \"myapp-dev\"])",
                        ),
                    ]),
                    "role": .object([
                        "type": .string("string"),
                        "description": .string("CFBundleTypeRole: Editor, Viewer, Shell, or None"),
                    ]),
                    "icon_file": .object([
                        "type": .string("string"),
                        "description": .string("CFBundleURLIconFile name (macOS only)"),
                    ]),
                    "additional_properties": .object([
                        "type": .string("string"),
                        "description": .string(
                            "JSON string of additional key-value pairs to set on the URL type entry",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("action"),
                    .string("name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let action = arguments.getString("action"),
              let name = arguments.getString("name")
        else {
            throw MCPError.invalidParams("project_path, target_name, action, and name are required")
        }

        guard ["add", "update", "remove"].contains(action) else {
            throw MCPError.invalidParams("action must be 'add', 'update', or 'remove'")
        }

        do {
            return try Self.editor.perform(
                action: action, name: name, projectPath: projectPath, targetName: targetName,
                pathUtility: pathUtility, arguments: arguments,
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    private static let editor = PlistArrayEditor(
        plistKey: "CFBundleURLTypes",
        primaryKey: "CFBundleURLName",
        noun: "URL type",
        applyFields: ManageURLTypeTool.applyFields,
    )

    private static func applyFields(
        to entry: inout [String: AnyValue],
        from arguments: [String: Value]
    ) {
        if let schemes = arguments.getOptionalStringArray("url_schemes") {
            entry["CFBundleURLSchemes"] = .strings(schemes)
        }
        if let role = arguments.getString("role") { entry["CFBundleTypeRole"] = .string(role) }
        if let iconFile = arguments.getString("icon_file") {
            entry["CFBundleURLIconFile"] = .string(iconFile)
        }

        PlistArrayEditor.applyAdditionalProperties(to: &entry, from: arguments)
    }
}
