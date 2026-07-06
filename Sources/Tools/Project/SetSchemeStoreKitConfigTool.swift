import MCP
import XCMCPCore
import Foundation

/// Adds or removes a `StoreKitConfigurationFileReference` on a scheme's `LaunchAction` and/or
/// `TestAction`.
///
/// Xcode stores the StoreKit configuration as a
/// `<StoreKitConfigurationFileReference identifier = "…">` child whose `identifier` is the path of
/// the `.storekit` file relative to the `.xcscheme` file's own location. The underlying XcodeProj
/// model only round-trips this element on `LaunchAction` — `TestAction`'s reference is silently
/// dropped on write — so this tool edits the scheme XML directly rather than through `XCScheme`,
/// preserving every other element exactly.
public struct SetSchemeStoreKitConfigTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    /// Actions whose StoreKit reference can be edited, in scheme serialization order.
    private static let actionElementNames: [String] = ["TestAction", "LaunchAction"]

    public func tool() -> Tool {
        .init(
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
                        "enum": .array([.string("launch"), .string("test"), .string("both")]),
                        "description": .string(
                            "Which scheme actions to edit: launch (Run), test (Test), or both (default)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("scheme_name")]),
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
                throw MCPError.invalidParams("target_actions must be 'launch', 'test', or 'both'")
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)

        guard let schemePath = SchemePathResolver.findScheme(
            named: schemeName, in: resolvedProjectPath,
        ) else { return Self.message("Scheme '\(schemeName)' not found in project") }

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
            let (edited, skipped) = try Self.applyStoreKitReference(
                schemePath: schemePath,
                identifier: identifier,
                isAdd: isAdd,
                elementNames: elementNames,
            )

            if edited.isEmpty {
                let verb = isAdd ? "set" : "remove"
                let detail = skipped.isEmpty
                    ? (isAdd ? "" : " (no reference was present)")
                    : " (\(skipped.joined(separator: ", ")) not present in scheme)"
                return Self.message(
                    "No StoreKit reference to \(verb) in scheme '\(schemeName)'\(detail)",
                )
            }

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

    // MARK: - Reusable scheme editing

    /// Action element names whose StoreKit reference can be edited, in scheme serialization order.
    /// Exposed so callers that unwire every action (e.g. `remove_file` on a `.storekit`) don't
    /// duplicate the list.
    public static let editableActionNames: [String] = actionElementNames

    /// Sets or clears the `<StoreKitConfigurationFileReference>` on the named actions of a scheme
    /// file, editing the XML in place and writing it back only when something actually changed.
    ///
    /// This is the shared core behind `set_scheme_storekit_config`, `add_storekit_config`, and the
    /// `remove_file` guardrail. Editing the raw XML (rather than round-tripping through `XCScheme`)
    /// preserves every other element exactly and, critically, never recomputes a *sibling* action's
    /// path — the reference is written verbatim from `identifier`, computed once relative to this
    /// scheme file, so unrelated actions can never have their relative depth mangled.
    ///
    /// - Parameters:
    ///   - schemePath: Absolute path to the `.xcscheme` file.
    ///   - identifier: Scheme-relative path to store (ignored when `isAdd` is false).
    ///   - isAdd: `true` to set the reference, `false` to clear it.
    ///   - elementNames: Which action elements to edit (`LaunchAction` / `TestAction`).
    /// - Returns: `edited` — action names that changed; `skipped` — action names absent from the
    ///   scheme.
    @discardableResult
    public static func applyStoreKitReference(
        schemePath: String,
        identifier: String,
        isAdd: Bool,
        elementNames: [String],
    ) throws -> (edited: [String], skipped: [String]) {
        var content = try String(contentsOfFile: schemePath, encoding: .utf8)
        let original = content

        var edited: [String] = []
        var skipped: [String] = []

        for elementName in elementNames {
            guard let block = actionBlockRange(named: elementName, in: content) else {
                skipped.append(elementName)
                continue
            }
            let actionIndent = leadingIndent(before: block.lowerBound, in: content)
            var blockText = String(content[block])
            let hadReference = removeStoreKitReference(in: &blockText, action: elementName)

            if isAdd {
                insertStoreKitReference(
                    identifier: identifier,
                    in: &blockText,
                    action: elementName,
                    actionIndent: actionIndent,
                )
                edited.append(elementName)
            } else if hadReference { edited.append(elementName) }
            content.replaceSubrange(block, with: blockText)
        }

        if content != original {
            try content.write(toFile: schemePath, atomically: true, encoding: .utf8)
        }
        return (edited, skipped)
    }

    /// Returns the raw `identifier` of the `<StoreKitConfigurationFileReference>` on each action of
    /// a scheme that has one, keyed by action element name (`LaunchAction` / `TestAction`).
    ///
    /// Used to detect which schemes reference a given `.storekit` (so `remove_file` can unwire
    /// them) and to validate that a stored reference still resolves to a file on disk.
    public static func storeKitIdentifiers(
        inSchemeAt schemePath: String,
    ) -> [String: String] {
        guard let content = try? String(contentsOfFile: schemePath, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]

        for elementName in actionElementNames {
            guard let block = actionBlockRange(named: elementName, in: content) else { continue }
            let blockText = String(content[block])
            if let identifier = storeKitIdentifier(in: blockText) {
                result[elementName] = identifier
            }
        }
        return result
    }

    /// Extracts the `identifier` attribute of the first `<StoreKitConfigurationFileReference>` in
    /// an action block, unescaping XML entities, or nil if none is present.
    private static func storeKitIdentifier(in blockText: String) -> String? {
        let pattern =
            "<StoreKitConfigurationFileReference\\b[\\s\\S]*?identifier\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(blockText.startIndex..<blockText.endIndex, in: blockText)
        guard let match = regex.firstMatch(in: blockText, range: range),
              let idRange = Range(match.range(at: 1), in: blockText) else { return nil }
        return String(blockText[idRange]).xmlAttributeUnescaped
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
                  of: "</\(name)>", range: open.upperBound..<content.endIndex,
              ) else { return nil }
        return open.lowerBound..<close.upperBound
    }

    /// Returns the whitespace between the line start and `index` (the indentation of that line).
    private static func leadingIndent(
        before index: String.Index,
        in content: String,
    ) -> String {
        let lineStart = content[..<index].lastIndex(of: "\n").map { content.index(after: $0) }
            ?? content.startIndex
        return String(content[lineStart..<index])
    }

    /// Removes any `<StoreKitConfigurationFileReference>` element (paired or self-closing),
    /// including its leading indentation and trailing newline, from an action block.
    ///
    /// - Returns: true if a reference was present and removed.
    private static func removeStoreKitReference(
        in blockText: inout String,
        action _: String,
    ) -> Bool {
        let pattern = "[ \\t]*<StoreKitConfigurationFileReference\\b"
            + "(?:[^>]*?/>|[\\s\\S]*?</StoreKitConfigurationFileReference>)[ \\t]*\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(blockText.startIndex..<blockText.endIndex, in: blockText)
        guard regex.firstMatch(in: blockText, range: range) != nil else { return false }
        blockText = regex.stringByReplacingMatches(in: blockText, range: range, withTemplate: "")
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
        let element = "\(childIndent)<StoreKitConfigurationFileReference\n"
            + "\(childIndent)   identifier = \"\(identifier.xmlAttributeEscaped)\">\n"
            + "\(childIndent)</StoreKitConfigurationFileReference>\n"
        blockText.replaceSubrange(lineStart..<lineStart, with: element)
    }

    /// Maps a scheme action element name to the user-facing verb (`LaunchAction` → "launch").
    public static func friendlyName(_ elementName: String) -> String {
        elementName == "LaunchAction" ? "launch" : "test"
    }

    private static func message(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}

fileprivate extension String {
    /// Escapes the five XML special characters for use inside a double-quoted attribute value.
    var xmlAttributeEscaped: String {
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

    /// Reverses ``xmlAttributeEscaped``, decoding the five predefined XML entities back to their
    /// characters. Applied when reading a stored `identifier` back off a scheme.
    var xmlAttributeUnescaped: String {
        replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
