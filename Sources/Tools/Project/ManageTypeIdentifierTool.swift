import MCP
import XCMCPCore

public struct ManageTypeIdentifierTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "manage_type_identifier",
            description:
                "Add, update, remove, or prune an exported or imported type identifier (UTExportedTypeDeclarations / UTImportedTypeDeclarations) in a target's Info.plist. For update/remove, target an entry by 'identifier', 'match_description', or 'match_index' (the number shown by list_type_identifiers) — the latter two let you repair declarations that are missing a UTTypeIdentifier. 'prune' deletes every declaration missing a UTTypeIdentifier (such entries are ignored by LaunchServices).",
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
                        "description": .string("Action to perform: add, update, remove, or prune"),
                        "enum": .array([
                            .string("add"), .string("update"), .string("remove"),
                            .string("prune"),
                        ]),
                    ]),
                    "kind": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Whether this is an exported or imported type identifier",
                        ),
                        "enum": .array([.string("exported"), .string("imported")]),
                    ]),
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string(
                            "UTTypeIdentifier (e.g. app.toba.thesis.project). Required for 'add'. For 'update'/'remove' it locates the entry; when the entry is instead located by match_description or match_index, 'identifier' is written onto it (use this to backfill a missing UTTypeIdentifier).",
                        ),
                    ]),
                    "match_description": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Locate the entry to update/remove by its UTTypeDescription instead of its identifier. Useful for declarations that have no UTTypeIdentifier.",
                        ),
                    ]),
                    "match_index": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Locate the entry to update/remove by its 1-based position within the exported/imported list (as numbered by list_type_identifiers). Useful for declarations that have no UTTypeIdentifier.",
                        ),
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("UTTypeDescription (human-readable description)"),
                    ]),
                    "conforms_to": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "UTTypeConformsTo array (e.g. [\"com.apple.package\"])",
                        ),
                    ]),
                    "extensions": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "File extensions (maps to UTTypeTagSpecification[\"public.filename-extension\"])",
                        ),
                    ]),
                    "mime_types": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "MIME types (maps to UTTypeTagSpecification[\"public.mime-type\"])",
                        ),
                    ]),
                    "reference_url": .object([
                        "type": .string("string"),
                        "description": .string("UTTypeReferenceURL"),
                    ]),
                    "icon_name": .object([
                        "type": .string("string"),
                        "description": .string("UTTypeIconName"),
                    ]),
                    "additional_properties": .object([
                        "type": .string("string"),
                        "description": .string(
                            "JSON string of additional key-value pairs to set on the type identifier entry",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("action"),
                    .string("kind"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let action = arguments.getString("action"),
              let kind = arguments.getString("kind")
        else {
            throw MCPError.invalidParams("project_path, target_name, action, and kind are required")
        }

        guard ["add", "update", "remove", "prune"].contains(action) else {
            throw MCPError.invalidParams("action must be 'add', 'update', 'remove', or 'prune'")
        }
        guard ["exported", "imported"].contains(kind) else {
            throw MCPError.invalidParams("kind must be 'exported' or 'imported'")
        }

        // 'add' is the only action that requires an identifier up front; for update/remove the
        // entry can be located by description or index.
        if action == "add", (arguments.getString("identifier") ?? "").isEmpty {
            throw MCPError.invalidParams("identifier is required for the 'add' action")
        }

        let kindLabel = kind == "exported" ? "exported" : "imported"
        let editor = PlistArrayEditor(
            plistKey: kind == "exported"
                ? "UTExportedTypeDeclarations"
                : "UTImportedTypeDeclarations",
            primaryKey: "UTTypeIdentifier",
            noun: "\(kindLabel) type identifier",
            applyFields: ManageTypeIdentifierTool.applyFields,
        )

        do {
            if action == "add" {
                return try editor.perform(
                    action: action, name: arguments.getString("identifier") ?? "",
                    projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
                    arguments: arguments,
                )
            }

            guard var session = try editor.open(
                projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
            ) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            switch action {
                case "update":
                    switch Self.locate(in: session.entries, arguments: arguments) {
                        case .noLocator:
                            return CallTool.Result.text(
                                "Provide 'identifier', 'match_description', or 'match_index' to identify the \(kindLabel) type declaration to update in target '\(targetName)'",
                            )
                        case .notFound:
                            return CallTool.Result.text(
                                "No matching \(kindLabel) type declaration found in target '\(targetName)'",
                            )
                        case let .found(index, byIdentifier):
                            var entry = session.entries[index]

                            // When the entry was located by description/index, an 'identifier'
                            // argument backfills (or renames) its missing UTTypeIdentifier.
                            if !byIdentifier,
                               let newIdentifier = arguments.getString("identifier"),
                               !newIdentifier.isEmpty
                            {
                                entry["UTTypeIdentifier"] = .string(newIdentifier)
                            }
                            Self.applyFields(to: &entry, from: arguments)

                            guard let finalID = entry["UTTypeIdentifier"]?.stringValue,
                                  !finalID.isEmpty
                            else {
                                return CallTool.Result.text(
                                    "Cannot update entry: the \(kindLabel) type declaration has no UTTypeIdentifier. Pass 'identifier' to backfill one (LaunchServices ignores declarations without it).",
                                )
                            }

                            session.entries[index] = entry
                            try session.save()

                            return CallTool.Result.text(
                                "Successfully updated \(kindLabel) type identifier '\(finalID)' in target '\(targetName)'",
                            )
                    }

                case "remove":
                    switch Self.locate(in: session.entries, arguments: arguments) {
                        case .noLocator:
                            return CallTool.Result.text(
                                "Provide 'identifier', 'match_description', or 'match_index' to identify the \(kindLabel) type declaration to remove from target '\(targetName)'",
                            )
                        case .notFound:
                            return CallTool.Result.text(
                                "No matching \(kindLabel) type declaration found in target '\(targetName)'",
                            )
                        case let .found(index, _):
                            let descriptor = Self.describe(session.entries[index])
                            session.entries.remove(at: index)
                            try session.save()

                            return CallTool.Result.text(
                                "Successfully removed \(kindLabel) type identifier \(descriptor) from target '\(targetName)'",
                            )
                    }

                case "prune":
                    let malformed = session.entries.filter(Self.isMalformed)

                    if malformed.isEmpty {
                        return CallTool.Result.text(
                            "No malformed \(kindLabel) type declarations (all have a UTTypeIdentifier) in target '\(targetName)'",
                        )
                    }

                    session.entries.removeAll(where: Self.isMalformed)
                    try session.save()

                    let removed = malformed.map(Self.describe).joined(separator: ", ")
                    return CallTool.Result.text(
                        "Pruned \(malformed.count) malformed \(kindLabel) type declaration(s) missing a UTTypeIdentifier from target '\(targetName)': \(removed)",
                    )

                default:
                    throw MCPError.invalidParams(
                        "action must be 'add', 'update', 'remove', or 'prune'",
                    )
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    /// LaunchServices ignores a declaration with no UTTypeIdentifier, so prune treats it as junk.
    private static func isMalformed(_ entry: [String: AnyValue]) -> Bool {
        entry["UTTypeIdentifier"]?.stringValue.map(\.isEmpty) ?? true
    }

    /// Outcome of resolving which declaration an update/remove targets.
    private enum LocateResult {
        /// Matched `index`; `byIdentifier` is true when matched via UTTypeIdentifier.
        case found(index: Int, byIdentifier: Bool)
        /// A locator was supplied but matched nothing.
        case notFound
        /// No locator argument (identifier / match_description / match_index) supplied.
        case noLocator
    }

    /// Resolves the target declaration from `match_index`, `match_description`, or `identifier` (in
    /// that precedence). The index/description locators let callers reach declarations that have no
    /// UTTypeIdentifier.
    private static func locate(
        in typeDecls: [[String: AnyValue]],
        arguments: [String: Value],
    ) -> LocateResult {
        if let matchIndex = arguments.getInt("match_index") {
            let zeroBased = matchIndex - 1
            guard typeDecls.indices.contains(zeroBased) else { return .notFound }
            return .found(index: zeroBased, byIdentifier: false)
        }
        if let description = arguments.getString("match_description") {
            guard let index = typeDecls.firstIndex(where: {
                $0["UTTypeDescription"]?.stringValue == description
            }) else { return .notFound }
            return .found(index: index, byIdentifier: false)
        }
        if let identifier = arguments.getString("identifier"), !identifier.isEmpty {
            guard let index = typeDecls.firstIndex(where: {
                $0["UTTypeIdentifier"]?.stringValue == identifier
            }) else { return .notFound }
            return .found(index: index, byIdentifier: true)
        }
        return .noLocator
    }

    /// Human-readable descriptor for an entry, preferring its identifier.
    private static func describe(_ entry: [String: AnyValue]) -> String {
        if let id = entry["UTTypeIdentifier"]?.stringValue, !id.isEmpty { return "'\(id)'" }
        if let desc = entry["UTTypeDescription"]?.stringValue { return "(description: '\(desc)')" }
        return "(entry without identifier)"
    }

    private static func applyFields(
        to entry: inout [String: AnyValue],
        from arguments: [String: Value]
    ) {
        if let desc = arguments.getString("description") {
            entry["UTTypeDescription"] = .string(desc)
        }
        if let conformsTo = arguments.getOptionalStringArray("conforms_to") {
            entry["UTTypeConformsTo"] = .strings(conformsTo)
        }

        // Build UTTypeTagSpecification from extensions and mime_types
        var tagSpec = entry["UTTypeTagSpecification"]?.dictionaryValue ?? [:]
        var tagSpecModified = false

        if let exts = arguments.getOptionalStringArray("extensions"), !exts.isEmpty {
            tagSpec["public.filename-extension"] = .strings(exts)
            tagSpecModified = true
        }
        if let mimes = arguments.getOptionalStringArray("mime_types"), !mimes.isEmpty {
            tagSpec["public.mime-type"] = .strings(mimes)
            tagSpecModified = true
        }
        if tagSpecModified { entry["UTTypeTagSpecification"] = .dictionary(tagSpec) }

        if let refURL = arguments.getString("reference_url") {
            entry["UTTypeReferenceURL"] = .string(refURL)
        }
        if let iconName = arguments.getString("icon_name") {
            entry["UTTypeIconName"] = .string(iconName)
        }

        PlistArrayEditor.applyAdditionalProperties(to: &entry, from: arguments)
    }
}
