import MCP
import XCMCPCore
import Foundation

public struct ListDocumentTypesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "list_document_types",
            description:
                "List all document types (CFBundleDocumentTypes) declared in a target's Info.plist",
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
                        "description": .string("Name of the target to list document types for"),
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

        do {
            let plist: [String: AnyValue]

            switch try InfoPlistUtility.readInfoPlist(
                projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
            ) {
                case let .message(text): return CallTool.Result.text(text)
                case let .plist(contents): plist = contents
            }

            guard let documentTypes = plist["CFBundleDocumentTypes"]?.arrayValue?
                .compactMap(\.dictionaryValue),
                  !documentTypes.isEmpty
            else {
                return CallTool.Result.text(
                    "No document types (CFBundleDocumentTypes) found in '\(targetName)'")
            }

            var output = "Document Types in target '\(targetName)':\n"

            for (index, docType) in documentTypes.enumerated() {
                let name = docType["CFBundleTypeName"]?.stringValue ?? "(unnamed)"
                output += "\n\(index + 1). \(name)\n"

                if let contentTypes = docType["LSItemContentTypes"]?.stringArrayValue,
                   !contentTypes.isEmpty
                {
                    output += "   Content Types: \(contentTypes.joined(separator: ", "))\n"
                }
                if let role = docType["CFBundleTypeRole"]?.stringValue {
                    output += "   Role: \(role)\n"
                }
                if let rank = docType["LSHandlerRank"]?.stringValue {
                    output += "   Handler Rank: \(rank)\n"
                }
                if let docClass = docType["NSDocumentClass"]?.stringValue {
                    output += "   Document Class: \(docClass)\n"
                }
                if let iconFile = docType["CFBundleTypeIconFile"]?.stringValue {
                    output += "   Icon File: \(iconFile)\n"
                }
                if let isPackage = docType["LSTypeIsPackage"]?.boolValue {
                    output += "   Is Package: \(isPackage)\n"
                }

                // Show any additional keys
                let knownKeys: Set = [
                    "CFBundleTypeName", "LSItemContentTypes", "CFBundleTypeRole",
                    "LSHandlerRank", "NSDocumentClass", "CFBundleTypeIconFile",
                    "LSTypeIsPackage",
                ]
                for (
                    key, value
                ) in docType.sorted(by: { $0.key < $1.key })
                    where !knownKeys.contains(key)
                { output += "   \(key): \(value.displayText)\n" }
            }

            return CallTool.Result.text(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw try error.asMCPError()
        }
    }
}
