import MCP
import XCMCPCore

public struct ManageDocumentTypeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "manage_document_type",
            description:
                "Add, update, or remove a document type (CFBundleDocumentTypes entry) in a target's Info.plist",
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
                            "Document type name (CFBundleTypeName). Used as the primary key for lookup.",
                        ),
                    ]),
                    "content_types": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "UTI strings for LSItemContentTypes (e.g. [\"app.toba.thesis.project\"])",
                        ),
                    ]),
                    "role": .object([
                        "type": .string("string"),
                        "description": .string(
                            "CFBundleTypeRole: Editor, Viewer, Shell, QLGenerator, or None",
                        ),
                    ]),
                    "handler_rank": .object([
                        "type": .string("string"),
                        "description": .string("LSHandlerRank: Owner, Default, Alternate, or None"),
                    ]),
                    "document_class": .object([
                        "type": .string("string"),
                        "description": .string("NSDocumentClass name"),
                    ]),
                    "icon_file": .object([
                        "type": .string("string"),
                        "description": .string("CFBundleTypeIconFile name"),
                    ]),
                    "is_package": .object([
                        "type": .string("boolean"),
                        "description": .string("LSTypeIsPackage boolean"),
                    ]),
                    "additional_properties": .object([
                        "type": .string("string"),
                        "description": .string(
                            "JSON string of additional key-value pairs to set on the document type entry",
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
        plistKey: "CFBundleDocumentTypes",
        primaryKey: "CFBundleTypeName",
        noun: "document type",
        applyFields: ManageDocumentTypeTool.applyFields,
    )

    private static func applyFields(
        to entry: inout [String: AnyValue],
        from arguments: [String: Value]
    ) {
        if let contentTypes = arguments.getOptionalStringArray("content_types") {
            entry["LSItemContentTypes"] = .strings(contentTypes)
        }
        if let role = arguments.getString("role") { entry["CFBundleTypeRole"] = .string(role) }
        if let rank = arguments.getString("handler_rank") { entry["LSHandlerRank"] = .string(rank) }
        if let docClass = arguments.getString("document_class") {
            entry["NSDocumentClass"] = .string(docClass)
        }
        if let iconFile = arguments.getString("icon_file") {
            entry["CFBundleTypeIconFile"] = .string(iconFile)
        }
        if let isPackage = arguments.getOptionalBool("is_package") {
            entry["LSTypeIsPackage"] = .boolean(isPackage)
        }

        PlistArrayEditor.applyAdditionalProperties(to: &entry, from: arguments)
    }
}
