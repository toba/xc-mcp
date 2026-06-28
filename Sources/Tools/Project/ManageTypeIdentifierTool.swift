import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ManageTypeIdentifierTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
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
                        "description": .string(
                            "Action to perform: add, update, remove, or prune",
                        ),
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
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(action) = arguments["action"],
              case let .string(kind) = arguments["kind"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, action, and kind are required",
            )
        }

        guard ["add", "update", "remove", "prune"].contains(action) else {
            throw MCPError.invalidParams("action must be 'add', 'update', 'remove', or 'prune'")
        }
        guard ["exported", "imported"].contains(kind) else {
            throw MCPError.invalidParams("kind must be 'exported' or 'imported'")
        }

        // 'add' is the only action that requires an identifier up front; for
        // update/remove the entry can be located by description or index.
        if action == "add", (arguments.getString("identifier") ?? "").isEmpty {
            throw MCPError.invalidParams("identifier is required for the 'add' action")
        }

        let plistKey =
            kind == "exported" ? "UTExportedTypeDeclarations" : "UTImportedTypeDeclarations"
        let kindLabel = kind == "exported" ? "exported" : "imported"

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectDir = projectURL.deletingLastPathComponent().path

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == targetName }) else {
                return CallTool.Result(
                    content: [.text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            }

            // Resolve or materialize Info.plist
            var plistPath = InfoPlistUtility.resolveInfoPlistPath(
                xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName,
            )

            if plistPath == nil {
                plistPath = try InfoPlistUtility.materializeInfoPlist(
                    xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName,
                    projectPath: Path(projectURL.path),
                )
            }

            guard let resolvedPlistPath = plistPath else {
                throw MCPError.internalError(
                    "Failed to resolve or create Info.plist for target '\(targetName)'",
                )
            }

            var plist = try InfoPlistUtility.readInfoPlist(path: resolvedPlistPath)
            var typeDecls = plist[plistKey] as? [[String: Any]] ?? []

            switch action {
                case "add":
                    let identifier = arguments.getString("identifier") ?? ""
                    if typeDecls.contains(where: {
                        ($0["UTTypeIdentifier"] as? String) == identifier
                    }) {
                        return Self.message(
                            "\(kindLabel.capitalized) type identifier '\(identifier)' already exists in target '\(targetName)'",
                        )
                    }

                    var entry: [String: Any] = ["UTTypeIdentifier": identifier]
                    applyFields(to: &entry, from: arguments)
                    typeDecls.append(entry)

                    plist[plistKey] = typeDecls
                    try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                    return Self.message(
                        "Successfully added \(kindLabel) type identifier '\(identifier)' to target '\(targetName)'",
                    )

                case "update":
                    switch Self.locate(in: typeDecls, arguments: arguments) {
                        case .noLocator:
                            return Self.message(
                                "Provide 'identifier', 'match_description', or 'match_index' to identify the \(kindLabel) type declaration to update in target '\(targetName)'",
                            )
                        case .notFound:
                            return Self.message(
                                "No matching \(kindLabel) type declaration found in target '\(targetName)'",
                            )
                        case let .found(index, byIdentifier):
                            var entry = typeDecls[index]

                            // When the entry was located by description/index, an
                            // 'identifier' argument backfills (or renames) its
                            // missing UTTypeIdentifier.
                            if !byIdentifier,
                               let newIdentifier = arguments.getString("identifier"),
                               !newIdentifier.isEmpty
                            {
                                entry["UTTypeIdentifier"] = newIdentifier
                            }
                            applyFields(to: &entry, from: arguments)

                            guard let finalID = entry["UTTypeIdentifier"] as? String,
                                  !finalID.isEmpty
                            else {
                                return Self.message(
                                    "Cannot update entry: the \(kindLabel) type declaration has no UTTypeIdentifier. Pass 'identifier' to backfill one (LaunchServices ignores declarations without it).",
                                )
                            }

                            typeDecls[index] = entry
                            plist[plistKey] = typeDecls
                            try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                            return Self.message(
                                "Successfully updated \(kindLabel) type identifier '\(finalID)' in target '\(targetName)'",
                            )
                    }

                case "remove":
                    switch Self.locate(in: typeDecls, arguments: arguments) {
                        case .noLocator:
                            return Self.message(
                                "Provide 'identifier', 'match_description', or 'match_index' to identify the \(kindLabel) type declaration to remove from target '\(targetName)'",
                            )
                        case .notFound:
                            return Self.message(
                                "No matching \(kindLabel) type declaration found in target '\(targetName)'",
                            )
                        case let .found(index, _):
                            let descriptor = Self.describe(typeDecls[index])
                            typeDecls.remove(at: index)

                            if typeDecls.isEmpty {
                                plist.removeValue(forKey: plistKey)
                            } else {
                                plist[plistKey] = typeDecls
                            }
                            try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                            return Self.message(
                                "Successfully removed \(kindLabel) type identifier \(descriptor) from target '\(targetName)'",
                            )
                    }

                case "prune":
                    let malformed = typeDecls.filter {
                        ($0["UTTypeIdentifier"] as? String).map(\.isEmpty) ?? true
                    }
                    if malformed.isEmpty {
                        return Self.message(
                            "No malformed \(kindLabel) type declarations (all have a UTTypeIdentifier) in target '\(targetName)'",
                        )
                    }

                    typeDecls.removeAll {
                        ($0["UTTypeIdentifier"] as? String).map(\.isEmpty) ?? true
                    }

                    if typeDecls.isEmpty {
                        plist.removeValue(forKey: plistKey)
                    } else {
                        plist[plistKey] = typeDecls
                    }
                    try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                    let removed = malformed.map(Self.describe).joined(separator: ", ")
                    return Self.message(
                        "Pruned \(malformed.count) malformed \(kindLabel) type declaration(s) missing a UTTypeIdentifier from target '\(targetName)': \(removed)",
                    )

                default:
                    throw MCPError.invalidParams(
                        "action must be 'add', 'update', 'remove', or 'prune'",
                    )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to manage type identifier: \(error.localizedDescription)",
            )
        }
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

    /// Resolves the target declaration from `match_index`, `match_description`, or
    /// `identifier` (in that precedence). The index/description locators let callers
    /// reach declarations that have no UTTypeIdentifier.
    private static func locate(
        in typeDecls: [[String: Any]], arguments: [String: Value],
    ) -> LocateResult {
        if let matchIndex = arguments.getInt("match_index") {
            let zeroBased = matchIndex - 1
            guard typeDecls.indices.contains(zeroBased) else { return .notFound }
            return .found(index: zeroBased, byIdentifier: false)
        }
        if let description = arguments.getString("match_description") {
            guard let index = typeDecls.firstIndex(where: {
                ($0["UTTypeDescription"] as? String) == description
            }) else { return .notFound }
            return .found(index: index, byIdentifier: false)
        }
        if let identifier = arguments.getString("identifier"), !identifier.isEmpty {
            guard let index = typeDecls.firstIndex(where: {
                ($0["UTTypeIdentifier"] as? String) == identifier
            }) else { return .notFound }
            return .found(index: index, byIdentifier: true)
        }
        return .noLocator
    }

    /// Human-readable descriptor for an entry, preferring its identifier.
    private static func describe(_ entry: [String: Any]) -> String {
        if let id = entry["UTTypeIdentifier"] as? String, !id.isEmpty { return "'\(id)'" }
        if let desc = entry["UTTypeDescription"] as? String {
            return "(description: '\(desc)')"
        }
        return "(entry without identifier)"
    }

    private static func message(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    private func applyFields(to entry: inout [String: Any], from arguments: [String: Value]) {
        if case let .string(desc) = arguments["description"] {
            entry["UTTypeDescription"] = desc
        }
        if case let .array(conformsTo) = arguments["conforms_to"] {
            entry["UTTypeConformsTo"] = conformsTo.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
        }

        // Build UTTypeTagSpecification from extensions and mime_types
        var tagSpec = entry["UTTypeTagSpecification"] as? [String: Any] ?? [:]
        var tagSpecModified = false

        if case let .array(extensions) = arguments["extensions"] {
            let exts = extensions.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
            if !exts.isEmpty {
                tagSpec["public.filename-extension"] = exts
                tagSpecModified = true
            }
        }
        if case let .array(mimeTypes) = arguments["mime_types"] {
            let mimes = mimeTypes.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
            if !mimes.isEmpty {
                tagSpec["public.mime-type"] = mimes
                tagSpecModified = true
            }
        }
        if tagSpecModified {
            entry["UTTypeTagSpecification"] = tagSpec
        }

        if case let .string(refURL) = arguments["reference_url"] {
            entry["UTTypeReferenceURL"] = refURL
        }
        if case let .string(iconName) = arguments["icon_name"] {
            entry["UTTypeIconName"] = iconName
        }
        if case let .string(jsonString) = arguments["additional_properties"],
           let additionalProps = try? JSONSerialization.jsonObject(with: Data(jsonString.utf8))
           as? [String: Any]
        {
            for (key, value) in additionalProps {
                entry[key] = value
            }
        }
    }
}
