import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Add, update and remove entries in an array of dictionaries inside a target's Info.plist
///
/// URL types, document types and UT type declarations are each an array of dictionaries identified
/// by one field. An editor carries the plist key, that identifying field and the noun used in
/// result text, so the tools over them differ only in those values and in the field applier they
/// supply.
public struct PlistArrayEditor: Sendable {
    /// Writes a tool's optional arguments onto one entry
    public typealias FieldApplier = @Sendable (inout [String: AnyValue], [String: Value]) -> Void

    /// The Info.plist key holding the array
    let plistKey: String
    /// The entry field that identifies one element
    let primaryKey: String
    /// Singular lowercase name of an entry, used in result text
    let noun: String
    let applyFields: FieldApplier

    public init(
        plistKey: String,
        primaryKey: String,
        noun: String,
        applyFields: @escaping FieldApplier,
    ) {
        self.plistKey = plistKey
        self.primaryKey = primaryKey
        self.noun = noun
        self.applyFields = applyFields
    }

    /// `noun` with its first character uppercased, for the start of a sentence
    private var capitalizedNoun: String { noun.prefix(1).uppercased() + noun.dropFirst() }

    /// An open Info.plist with the array under one key lifted out for editing
    public struct Session {
        /// The entries under the editor's plist key
        public var entries: [[String: AnyValue]]
        private var plist: [String: AnyValue]
        private let plistPath: String
        private let plistKey: String

        init(
            entries: [[String: AnyValue]],
            plist: [String: AnyValue],
            plistPath: String,
            plistKey: String,
        ) {
            self.entries = entries
            self.plist = plist
            self.plistPath = plistPath
            self.plistKey = plistKey
        }

        /// Writes `entries` back to disk, dropping the key when no entry remains
        public func save() throws {
            var plist = plist

            if entries.isEmpty {
                plist.removeValue(forKey: plistKey)
            } else {
                plist[plistKey] = .dictionaries(entries)
            }
            try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)
        }
    }

    /// Opens the target's Info.plist, creating one when the target has no physical plist
    ///
    /// - Returns: The session, or `nil` when the project holds no target of that name.
    public func open(
        projectPath: String,
        targetName: String,
        pathUtility: PathUtility,
    ) throws -> Session? {
        guard let loaded = try InfoPlistUtility.loadProject(
            projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
        ) else { return nil }

        var plistPath = InfoPlistUtility.resolveInfoPlistPath(
            xcodeproj: loaded.xcodeproj, projectDir: loaded.projectDir, targetName: targetName,
        )

        if plistPath == nil {
            plistPath = try InfoPlistUtility.materializeInfoPlist(
                xcodeproj: loaded.xcodeproj, projectDir: loaded.projectDir,
                targetName: targetName, projectPath: Path(loaded.projectURL.path),
            )
        }

        guard let resolvedPlistPath = plistPath else {
            throw MCPError.internalError(
                "Failed to resolve or create Info.plist for target '\(targetName)'",
            )
        }

        let plist = try InfoPlistUtility.readInfoPlist(path: resolvedPlistPath)

        return Session(
            entries: plist[plistKey]?.dictionaryArrayValue ?? [],
            plist: plist,
            plistPath: resolvedPlistPath,
            plistKey: plistKey,
        )
    }

    /// Runs one add, update or remove against the target's plist array
    ///
    /// - Parameters:
    ///   - action: `add`, `update` or `remove`
    ///   - name: The value of the identifying field that selects the entry
    ///   - arguments: The tool arguments, handed to the field applier on add and update
    /// - Returns: The result the tool returns to the client.
    /// - Throws: `MCPError.invalidParams` when `action` is none of the three.
    public func perform(
        action: String,
        name: String,
        projectPath: String,
        targetName: String,
        pathUtility: PathUtility,
        arguments: [String: Value],
    ) throws -> CallTool.Result {
        guard var session = try open(
            projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
        ) else {
            return CallTool.Result.text("Target '\(targetName)' not found in project")
        }

        let index = session.entries.firstIndex { $0[primaryKey]?.stringValue == name }

        switch action {
            case "add":
                guard index == nil else {
                    return CallTool.Result.text(
                        "\(capitalizedNoun) '\(name)' already exists in target '\(targetName)'")
                }

                var entry: [String: AnyValue] = [primaryKey: .string(name)]
                applyFields(&entry, arguments)
                session.entries.append(entry)
                try session.save()

                return CallTool.Result.text(
                    "Successfully added \(noun) '\(name)' to target '\(targetName)'")

            case "update":
                guard let index else {
                    return CallTool.Result.text(
                        "\(capitalizedNoun) '\(name)' not found in target '\(targetName)'")
                }

                var entry = session.entries[index]
                applyFields(&entry, arguments)
                session.entries[index] = entry
                try session.save()

                return CallTool.Result.text(
                    "Successfully updated \(noun) '\(name)' in target '\(targetName)'")

            case "remove":
                guard let index else {
                    return CallTool.Result.text(
                        "\(capitalizedNoun) '\(name)' not found in target '\(targetName)'")
                }

                session.entries.remove(at: index)
                try session.save()

                return CallTool.Result.text(
                    "Successfully removed \(noun) '\(name)' from target '\(targetName)'")

            default: throw MCPError.invalidParams("action must be 'add', 'update', or 'remove'")
        }
    }

    /// Merges the `additional_properties` JSON object argument onto an entry
    ///
    /// Every tool over a plist array accepts the same escape hatch for keys it has no named
    /// argument for. A value that is absent or not a JSON object leaves the entry unchanged.
    public static func applyAdditionalProperties(
        to entry: inout [String: AnyValue],
        from arguments: [String: Value],
    ) {
        guard let jsonString = arguments.getString("additional_properties"),
              let additionalProps = try? JSONDecoder().decode(
                  [String: AnyValue].self, from: Data(jsonString.utf8),
              ) else { return }

        for (key, value) in additionalProps { entry[key] = value }
    }
}
