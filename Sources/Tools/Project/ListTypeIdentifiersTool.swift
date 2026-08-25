import MCP
import XCMCPCore
import Foundation

public struct ListTypeIdentifiersTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "list_type_identifiers",
            description:
                "List exported and/or imported type identifiers (UTExportedTypeDeclarations / UTImportedTypeDeclarations) from a target's Info.plist",
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
                        "description": .string("Name of the target to list type identifiers for"),
                    ]),
                    "kind": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Which type identifiers to list: exported, imported, or all (default: all)",
                        ),
                        "enum": .array([.string("exported"), .string("imported"), .string("all")]),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name")
        else { throw MCPError.invalidParams("project_path and target_name are required") }

        let kind = arguments.getString("kind") ?? "all"

        guard ["exported", "imported", "all"].contains(kind) else {
            throw MCPError.invalidParams("kind must be 'exported', 'imported', or 'all'")
        }

        do {
            let plist: [String: AnyValue]

            switch try InfoPlistUtility.readInfoPlist(
                projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
            ) {
                case let .message(text): return CallTool.Result.text(text)
                case let .plist(contents): plist = contents
            }

            var output = ""
            var foundAny = false

            if kind == "exported" || kind == "all" {
                if let exported = plist["UTExportedTypeDeclarations"]?.arrayValue?
                    .compactMap(\.dictionaryValue),
                   !exported.isEmpty
                {
                    foundAny = true
                    output += "Exported Type Identifiers in target '\(targetName)':\n"
                    output += formatTypeIdentifiers(exported)
                }
            }

            if kind == "imported" || kind == "all" {
                if let imported = plist["UTImportedTypeDeclarations"]?.arrayValue?
                    .compactMap(\.dictionaryValue),
                   !imported.isEmpty
                {
                    foundAny = true
                    if !output.isEmpty { output += "\n" }
                    output += "Imported Type Identifiers in target '\(targetName)':\n"
                    output += formatTypeIdentifiers(imported)
                }
            }

            if !foundAny {
                let kindLabel: String

                switch kind {
                    case "exported": kindLabel = "exported"
                    case "imported": kindLabel = "imported"
                    default: kindLabel = "exported or imported"
                }
                return CallTool.Result.text(
                    "No \(kindLabel) type identifiers found in target '\(targetName)'")
            }

            return CallTool.Result.text(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw try error.asMCPError()
        }
    }

    private func formatTypeIdentifiers(_ identifiers: [[String: AnyValue]]) -> String {
        var output = ""

        for (index, uti) in identifiers.enumerated() {
            let identifier = uti["UTTypeIdentifier"]?.stringValue ?? "(no identifier)"
            output += "\n\(index + 1). \(identifier)\n"

            if let description = uti["UTTypeDescription"]?.stringValue {
                output += "   Description: \(description)\n"
            }
            if let conformsTo = uti["UTTypeConformsTo"]?.stringArrayValue, !conformsTo.isEmpty {
                output += "   Conforms To: \(conformsTo.joined(separator: ", "))\n"
            }

            // stringArrayValue reads a lone string as a one-element array, which is the other shape
            // Xcode writes for both of these keys
            if let tagSpec = uti["UTTypeTagSpecification"]?.dictionaryValue {
                if let extensions = tagSpec["public.filename-extension"]?.stringArrayValue,
                   !extensions.isEmpty
                {
                    output += "   Extensions: \(extensions.joined(separator: ", "))\n"
                }
                if let mimeTypes = tagSpec["public.mime-type"]?.stringArrayValue,
                   !mimeTypes.isEmpty {
                    output += "   MIME Types: \(mimeTypes.joined(separator: ", "))\n"
                }
            }
            if let refURL = uti["UTTypeReferenceURL"]?.stringValue {
                output += "   Reference URL: \(refURL)\n"
            }
            if let iconName = uti["UTTypeIconName"]?.stringValue {
                output += "   Icon: \(iconName)\n"
            }

            // Show any additional keys
            let knownKeys: Set = [
                "UTTypeIdentifier", "UTTypeDescription", "UTTypeConformsTo",
                "UTTypeTagSpecification", "UTTypeReferenceURL", "UTTypeIconName",
            ]
            for (
                key, value
            ) in uti.sorted(by: { $0.key < $1.key })
                where !knownKeys.contains(key)
            { output += "   \(key): \(value.displayText)\n" }
        }

        return output
    }
}
