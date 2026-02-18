import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct ListDocumentTypesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_document_types",
            description:
                "List all document types (CFBundleDocumentTypes) declared in a target's Info.plist",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to list document types for"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectDir = projectURL.deletingLastPathComponent().path

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == targetName }) else {
                return CallTool.Result(
                    content: [.text("Target '\(targetName)' not found in project")]
                )
            }

            guard
                let plistPath = InfoPlistUtility.resolveInfoPlistPath(
                    xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName)
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            "No Info.plist found for target '\(targetName)'. The target may use a generated Info.plist with no physical file."
                        )
                    ]
                )
            }

            let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)

            guard let documentTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]],
                !documentTypes.isEmpty
            else {
                return CallTool.Result(
                    content: [
                        .text("No document types (CFBundleDocumentTypes) found in '\(targetName)'")
                    ]
                )
            }

            var output = "Document Types in target '\(targetName)':\n"

            for (index, docType) in documentTypes.enumerated() {
                let name = docType["CFBundleTypeName"] as? String ?? "(unnamed)"
                output += "\n\(index + 1). \(name)\n"

                if let contentTypes = docType["LSItemContentTypes"] as? [String],
                    !contentTypes.isEmpty
                {
                    output += "   Content Types: \(contentTypes.joined(separator: ", "))\n"
                }
                if let role = docType["CFBundleTypeRole"] as? String {
                    output += "   Role: \(role)\n"
                }
                if let rank = docType["LSHandlerRank"] as? String {
                    output += "   Handler Rank: \(rank)\n"
                }
                if let docClass = docType["NSDocumentClass"] as? String {
                    output += "   Document Class: \(docClass)\n"
                }
                if let iconFile = docType["CFBundleTypeIconFile"] as? String {
                    output += "   Icon File: \(iconFile)\n"
                }
                if let isPackage = docType["LSTypeIsPackage"] as? Bool {
                    output += "   Is Package: \(isPackage)\n"
                }

                // Show any additional keys
                let knownKeys: Set<String> = [
                    "CFBundleTypeName", "LSItemContentTypes", "CFBundleTypeRole",
                    "LSHandlerRank", "NSDocumentClass", "CFBundleTypeIconFile",
                    "LSTypeIsPackage",
                ]
                let additionalKeys = docType.keys.filter { !knownKeys.contains($0) }.sorted()
                for key in additionalKeys {
                    output += "   \(key): \(docType[key]!)\n"
                }
            }

            return CallTool.Result(content: [
                .text(output.trimmingCharacters(in: .whitespacesAndNewlines))
            ])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to list document types: \(error.localizedDescription)")
        }
    }
}
