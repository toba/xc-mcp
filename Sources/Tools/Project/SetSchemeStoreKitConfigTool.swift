import Foundation
import MCP
import XCMCPCore

/// Adds or removes a `StoreKitConfigurationFileReference` on a scheme's `LaunchAction` and/or
/// `TestAction`.
///
/// Xcode stores the StoreKit configuration as a `<StoreKitConfigurationFileReference identifier
/// = "…">` child whose `identifier` is the path of the `.storekit` file relative to the
/// `.xcscheme` file's own location. The underlying XcodeProj model only round-trips this element
/// on `LaunchAction` — `TestAction`'s reference is silently dropped on write — so this tool edits
/// the scheme XML directly rather than through `XCScheme`, preserving every other element exactly.
public struct SetSchemeStoreKitConfigTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    /// Actions whose StoreKit reference can be edited, in scheme serialization order.
    private static let actionElementNames: [String] = ["TestAction", "LaunchAction"]

    public func tool() -> Tool {
        Tool(
            name: "set_scheme_storekit_config",
            description: """
            Set or clear a scheme's StoreKit configuration (.storekit) reference. Writes the \
            <StoreKitConfigurationFileReference> child under the scheme's LaunchAction (Run) and/or \
            TestAction (Test), storing the path relative to the scheme file. Use action=add to set \
            (idempotent — replaces any existing reference) or action=remove to clear it. Edits the \
            scheme XML directly so an existing TestAction reference is preserved.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "scheme_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the existing scheme"),
                    ]),
                    "storekit_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .storekit configuration file (required for action=add)",
                        ),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([.string("add"), .string("remove")]),
                        "description": .string(
                            "add to set the reference (default), remove to clear it",
                        ),
                    ]),
                    "target_actions": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("launch"), .string("test"), .string("both"),
                        ]),
                        "description": .string(
                            "Which scheme actions to edit: launch (Run), test (Test), or both (default)",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("scheme_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let projectPath = try arguments.getRequiredString("project_path")
        let schemeName = try arguments.getRequiredString("scheme_name")

        let action = arguments.getString("action") ?? "add"
        guard action == "add" || action == "remove" else {
            throw MCPError.invalidParams("action must be 'add' or 'remove'")
        }
        let isAdd = action == "add"

        let targetActions = arguments.getString("target_actions") ?? "both"
        let elementNames: [String]
        switch targetActions {
            case "launch": elementNames = ["LaunchAction"]
            case "test": elementNames = ["TestAction"]
            case "both": elementNames = Self.actionElementNames
            default:
                throw MCPError.invalidParams(
                    "target_actions must be 'launch', 'test', or 'both'",
                )
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)

        guard
            let schemePath = SchemePathResolver.findScheme(
                named: schemeName, in: resolvedProjectPath,
            )
        else {
            return Self.message("Scheme '\(schemeName)' not found in project")
        }

        // Compute the scheme-relative identifier only when adding a reference.
        var identifier = ""
        if isAdd {
            guard let storekitPath = arguments.getString("storekit_path") else {
                throw MCPError.invalidParams("storekit_path is required when action is 'add'")
            }
            let resolvedStorekitPath = try pathUtility.resolvePath(from: storekitPath)
            guard FileManager.default.fileExists(atPath: resolvedStorekitPath) else {
                return Self.message("StoreKit configuration not found at \(resolvedStorekitPath)")
            }
            identifier = SchemePathResolver.schemeRelativeIdentifier(
                for: resolvedStorekitPath, schemePath: schemePath,
            )
        }

        do {
            var content = try String(contentsOfFile: schemePath, encoding: .utf8)

            var edited: [String] = []
            var skipped: [String] = []
            for elementName in elementNames {
                guard let block = Self.actionBlockRange(named: elementName, in: content) else {
                    skipped.append(elementName)
                    continue
                }
                let actionIndent = Self.leadingIndent(before: block.lowerBound, in: content)
                var blockText = String(content[block])
                let hadReference = Self.removeStoreKitReference(in: &blockText, action: elementName)
                if isAdd {
                    Self.insertStoreKitReference(
                        identifier: identifier,
                        in: &blockText,
                        action: elementName,
                        actionIndent: actionIndent,
                    )
                    edited.append(elementName)
                } else if hadReference {
                    edited.append(elementName)
                }
                content.replaceSubrange(block, with: blockText)
            }

            if edited.isEmpty {
                let verb = isAdd ? "set" : "remove"
                let detail = skipped.isEmpty
                    ? (isAdd ? "" : " (no reference was present)")
                    : " (\(skipped.joined(separator: ", ")) not present in scheme)"
                return Self.message(
                    "No StoreKit reference to \(verb) in scheme '\(schemeName)'\(detail)",
                )
            }

            try content.write(toFile: schemePath, atomically: true, encoding: .utf8)

            let actionList = edited.map(Self.friendlyName).joined(separator: " + ")
            let summary = isAdd
                ? "Set StoreKit config '\(identifier)' on \(actionList) of scheme '\(schemeName)'"
                : "Removed StoreKit config from \(actionList) of scheme '\(schemeName)'"
            let note = skipped.isEmpty
                ? ""
                : " (skipped: \(skipped.map(Self.friendlyName).joined(separator: ", ")) not present)"
            return Self.message(summary + note)
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to edit scheme StoreKit config: \(error.localizedDescription)",
            )
        }
    }

    // MARK: - XML editing

    /// Returns the range of an action block — from the start of its opening `<ActionName` tag
    /// through the end of its `</ActionName>` closing tag — or nil if the action is absent.
    private static func actionBlockRange(
        named name: String,
        in content: String,
    ) -> Range<String.Index>? {
        guard let open = content.range(of: "<\(name)"),
              let close = content.range(
                  of: "</\(name)>", range: open.upperBound ..< content.endIndex,
              )
        else {
            return nil
        }
        return open.lowerBound ..< close.upperBound
    }

    /// Returns the whitespace between the line start and `index` (the indentation of that line).
    private static func leadingIndent(
        before index: String.Index,
        in content: String,
    ) -> String {
        let lineStart = content[..<index].lastIndex(of: "\n").map { content.index(after: $0) }
            ?? content.startIndex
        return String(content[lineStart ..< index])
    }

    /// Removes any `<StoreKitConfigurationFileReference>` element (paired or self-closing),
    /// including its leading indentation and trailing newline, from an action block.
    ///
    /// - Returns: true if a reference was present and removed.
    private static func removeStoreKitReference(
        in blockText: inout String,
        action _: String,
    ) -> Bool {
        let pattern =
            "[ \\t]*<StoreKitConfigurationFileReference\\b" +
            "(?:[^>]*?/>|[\\s\\S]*?</StoreKitConfigurationFileReference>)[ \\t]*\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(blockText.startIndex ..< blockText.endIndex, in: blockText)
        guard regex.firstMatch(in: blockText, range: range) != nil else { return false }
        blockText = regex.stringByReplacingMatches(
            in: blockText, range: range, withTemplate: "",
        )
        return true
    }

    /// Inserts a `<StoreKitConfigurationFileReference>` as the last child of an action block,
    /// immediately before its closing tag, matching Xcode's indentation.
    private static func insertStoreKitReference(
        identifier: String,
        in blockText: inout String,
        action: String,
        actionIndent: String,
    ) {
        guard let close = blockText.range(of: "</\(action)>", options: .backwards) else { return }
        let lineStart = blockText[..<close.lowerBound].lastIndex(of: "\n")
            .map { blockText.index(after: $0) } ?? close.lowerBound
        let childIndent = actionIndent + "   "
        let element =
            "\(childIndent)<StoreKitConfigurationFileReference\n" +
            "\(childIndent)   identifier = \"\(identifier.xmlAttributeEscaped)\">\n" +
            "\(childIndent)</StoreKitConfigurationFileReference>\n"
        blockText.replaceSubrange(lineStart ..< lineStart, with: element)
    }

    private static func friendlyName(_ elementName: String) -> String {
        elementName == "LaunchAction" ? "launch" : "test"
    }

    private static func message(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}

extension String {
    /// Escapes the five XML special characters for use inside a double-quoted attribute value.
    fileprivate var xmlAttributeEscaped: String {
        var result = ""
        result.reserveCapacity(count)
        for character in self {
            switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\"": result += "&quot;"
                case "'": result += "&apos;"
                default: result.append(character)
            }
        }
        return result
    }
}
