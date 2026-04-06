import Foundation

/// Surgical text-based editor for pbxproj files.
///
/// XcodeProj's round-trip serializer corrupts unrelated sections (strips comments,
/// adds spurious fields, reformats arrays). These helpers use XcodeProj for
/// reading/validation only, then make targeted text edits to the pbxproj file.
public enum PBXProjTextEditor {
    public enum EditError: Error, CustomStringConvertible {
        case blockNotFound(uuid: String)
        case arrayFieldNotFound(field: String, inBlock: String)
        case sectionNotFound(String)
        case fileNotFound(String)

        public var description: String {
            switch self {
                case let .blockNotFound(uuid):
                    "Block with UUID '\(uuid)' not found in pbxproj"
                case let .arrayFieldNotFound(field, block):
                    "Array field '\(field)' not found in block '\(block)'"
                case let .sectionNotFound(section):
                    "Section '\(section)' not found in pbxproj"
                case let .fileNotFound(path):
                    "File not found: \(path)"
            }
        }
    }

    // MARK: - File I/O

    public static func read(projectPath: String) throws(EditError) -> String {
        let path = "\(projectPath)/project.pbxproj"
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)
        else {
            throw .fileNotFound(path)
        }
        return content
    }

    public static func write(_ content: String, projectPath: String) throws {
        let path = "\(projectPath)/project.pbxproj"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Block operations

    /// Remove an entire object block (from its UUID line through closing `};`).
    public static func removeBlock(
        _ content: String, uuid: String,
    ) throws(EditError) -> String {
        var lines = content.splitLines()
        let (start, end) = try findBlock(in: lines, uuid: uuid)
        lines.removeSubrange(start ... end)
        return lines.joined(separator: "\n")
    }

    /// Insert a new `PBXFileSystemSynchronizedBuildFileExceptionSet` block
    /// into its section (creating the section if needed).
    public static func insertExceptionSetBlock(
        _ content: String,
        uuid: String,
        folderName: String,
        targetName: String,
        targetUUID: String,
        membershipExceptions: [String],
    ) throws(EditError) -> String {
        let comment =
            "Exceptions for \"\(folderName)\" folder in \"\(targetName)\" target"

        var block: [String] = []
        block.append("\t\t\(uuid) /* \(comment) */ = {")
        block.append(
            "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;",
        )
        block.append("\t\t\tmembershipExceptions = (")
        for file in membershipExceptions {
            block.append("\t\t\t\t\(quotePBX(file)),")
        }
        block.append("\t\t\t);")
        block.append("\t\t\ttarget = \(targetUUID) /* \(targetName) */;")
        block.append("\t\t};")

        var lines = content.splitLines()
        let sectionEnd =
            "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */"

        if let idx = lines.firstIndex(where: { $0.contains(sectionEnd) }) {
            lines.insert(contentsOf: block, at: idx)
            return lines.joined(separator: "\n")
        }

        // Section doesn't exist — create it before the next alphabetical section
        let markers = [
            "/* Begin PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet section */",
            "/* Begin PBXFileSystemSynchronizedRootGroup section */",
            "/* Begin PBXFrameworksBuildPhase section */",
            "/* Begin PBXGroup section */",
        ]
        for marker in markers {
            if let idx = lines.firstIndex(where: { $0.contains(marker) }) {
                var section = [""]
                section.append(
                    "/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */",
                )
                section.append(contentsOf: block)
                section.append(sectionEnd)
                lines.insert(contentsOf: section, at: idx)
                return lines.joined(separator: "\n")
            }
        }
        throw EditError.sectionNotFound(
            "PBXFileSystemSynchronizedBuildFileExceptionSet",
        )
    }

    // MARK: - Array entry operations (plain values like filenames)

    /// Add plain entries (e.g. filenames) to an existing array field.
    public static func addEntriesToArray(
        _ content: String,
        blockUUID: String,
        field: String,
        entries: [String],
    ) throws(EditError) -> String {
        var lines = content.splitLines()
        let (_, arrayEnd) = try findArrayField(
            in: lines, blockUUID: blockUUID, field: field,
        )
        let indent = detectEntryIndent(
            in: lines, blockUUID: blockUUID, field: field,
        )

        var newLines: [String] = []
        for entry in entries {
            newLines.append("\(indent)\(quotePBX(entry)),")
        }
        lines.insert(contentsOf: newLines, at: arrayEnd)
        return lines.joined(separator: "\n")
    }

    /// Remove plain entries from an array field.
    /// Returns modified content and number of entries remaining.
    public static func removeEntriesFromArray(
        _ content: String,
        blockUUID: String,
        field: String,
        entries: Set<String>,
    ) throws(EditError) -> (content: String, remainingCount: Int) {
        var lines = content.splitLines()
        let (arrayStart, arrayEnd) = try findArrayField(
            in: lines, blockUUID: blockUUID, field: field,
        )

        var toRemove: [Int] = []
        for i in (arrayStart + 1) ..< arrayEnd {
            if let name = extractPlainEntry(lines[i]), entries.contains(name) {
                toRemove.append(i)
            }
        }
        for i in toRemove.reversed() { lines.remove(at: i) }

        let newEnd = arrayEnd - toRemove.count
        var remaining = 0
        for i in (arrayStart + 1) ..< newEnd {
            if extractPlainEntry(lines[i]) != nil { remaining += 1 }
        }
        return (lines.joined(separator: "\n"), remaining)
    }

    // MARK: - Array reference operations (UUID references with comments)

    /// Add a UUID reference to an array field, creating the field if absent.
    public static func addReference(
        _ content: String,
        blockUUID: String,
        field: String,
        refUUID: String,
        comment: String,
    ) throws(EditError) -> String {
        if hasField(content, blockUUID: blockUUID, field: field) {
            var lines = content.splitLines()
            let (_, arrayEnd) = try findArrayField(
                in: lines, blockUUID: blockUUID, field: field,
            )
            let indent = detectEntryIndent(
                in: lines, blockUUID: blockUUID, field: field,
            )
            lines.insert(
                "\(indent)\(refUUID) /* \(comment) */,", at: arrayEnd,
            )
            return lines.joined(separator: "\n")
        }
        return try insertFieldWithReferences(
            content, blockUUID: blockUUID, field: field,
            references: [(refUUID, comment)],
        )
    }

    /// Remove a UUID reference from an array field.
    /// Removes the entire field if it becomes empty.
    public static func removeReference(
        _ content: String,
        blockUUID: String,
        field: String,
        refUUID: String,
    ) throws(EditError) -> String {
        var lines = content.splitLines()
        let (arrayStart, arrayEnd) = try findArrayField(
            in: lines, blockUUID: blockUUID, field: field,
        )

        guard let idx = ((arrayStart + 1) ..< arrayEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix(refUUID)
        }) else {
            return content
        }

        lines.remove(at: idx)

        // If array is now empty, remove the entire field
        let newEnd = arrayEnd - 1
        let empty = !((arrayStart + 1) ..< newEnd).contains {
            !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        if empty {
            lines.removeSubrange(arrayStart ... newEnd)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Section block insertion

    /// Insert block lines into a named section (e.g. "PBXBuildFile").
    /// Creates the section at the correct alphabetical position if it doesn't exist.
    public static func insertBlockInSection(
        _ content: String,
        section: String,
        blockLines: [String],
    ) throws(EditError) -> String {
        var lines = content.splitLines()
        let sectionEnd = "/* End \(section) section */"

        if let idx = lines.firstIndex(where: { $0.contains(sectionEnd) }) {
            lines.insert(contentsOf: blockLines, at: idx)
            return lines.joined(separator: "\n")
        }

        // Section doesn't exist — create it at the correct alphabetical position
        var insertionPoint: Int?
        for (i, line) in lines.enumerated() {
            if let beginRange = line.range(of: "/* Begin "),
               let endRange = line.range(of: " section */")
            {
                let existing = String(line[beginRange.upperBound ..< endRange.lowerBound])
                if existing > section {
                    insertionPoint = i
                    break
                }
            }
        }

        guard let ip = insertionPoint else {
            throw EditError.sectionNotFound(section)
        }

        var newSection = [""]
        newSection.append("/* Begin \(section) section */")
        newSection.append(contentsOf: blockLines)
        newSection.append("/* End \(section) section */")
        lines.insert(contentsOf: newSection, at: ip)
        return lines.joined(separator: "\n")
    }

    // MARK: - Build setting operations

    /// Add an array build setting to a configuration, only if the key doesn't already exist.
    public static func addBuildSettingArray(
        _ content: String,
        configUUID: String,
        key: String,
        values: [String],
    ) throws(EditError) -> String {
        var lines = content.splitLines()
        let (bStart, bEnd) = try findBlock(in: lines, uuid: configUUID)

        // Check if key already exists in this block
        for i in bStart ... bEnd {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("\(key) ") {
                return content // Already set
            }
        }

        // Find buildSettings = { … }; within the block
        guard let settingsStart = (bStart ... bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("buildSettings = {")
        }) else {
            throw .arrayFieldNotFound(field: "buildSettings", inBlock: configUUID)
        }

        // Find the closing }; for buildSettings by tracking brace depth
        var depth = 0
        var settingsEnd: Int?
        for i in settingsStart ... bEnd {
            for c in lines[i] {
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1 }
            }
            if depth == 0 {
                settingsEnd = i
                break
            }
        }

        guard let se = settingsEnd else {
            throw .arrayFieldNotFound(field: "buildSettings", inBlock: configUUID)
        }

        // Detect indent from existing settings entries
        let settingsIndent: String
        if settingsStart + 1 < se {
            settingsIndent = String(
                lines[settingsStart + 1].prefix(while: { $0 == "\t" || $0 == " " }),
            )
        } else {
            settingsIndent = "\t\t\t\t"
        }
        let valueIndent = settingsIndent + "\t"

        var insert: [String] = []
        insert.append("\(settingsIndent)\(key) = (")
        for v in values {
            insert.append("\(valueIndent)\(quotePBX(v)),")
        }
        insert.append("\(settingsIndent));")

        lines.insert(contentsOf: insert, at: se)
        return lines.joined(separator: "\n")
    }

    // MARK: - UUID generation

    public static func generateUUID() -> String {
        (0 ..< 24).map { _ in
            "0123456789ABCDEF".randomElement().map(String.init)!
        }.joined()
    }

    // MARK: - Internals

    private static func findBlock(
        in lines: [String], uuid: String,
    ) throws(EditError) -> (start: Int, end: Int) {
        // Match block definitions (UUID ... = {) not array references (UUID ... ,)
        guard let start = lines.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return (t.hasPrefix("\(uuid) ") || t.hasPrefix("\(uuid)\t"))
                && t.contains("= {")
        }) else {
            throw .blockNotFound(uuid: uuid)
        }
        var depth = 0
        for i in start ..< lines.count {
            for c in lines[i] {
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1 }
            }
            if depth == 0 { return (start, i) }
        }
        throw .blockNotFound(uuid: uuid)
    }

    private static func findArrayField(
        in lines: [String], blockUUID: String, field: String,
    ) throws(EditError) -> (start: Int, end: Int) {
        let (bStart, bEnd) = try findBlock(in: lines, uuid: blockUUID)
        guard let aStart = (bStart ... bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces)
                .hasPrefix("\(field) = (")
        }) else {
            throw .arrayFieldNotFound(field: field, inBlock: blockUUID)
        }
        guard let aEnd = ((aStart + 1) ... bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces) == ");"
        }) else {
            throw .arrayFieldNotFound(field: field, inBlock: blockUUID)
        }
        return (aStart, aEnd)
    }

    private static func hasField(
        _ content: String, blockUUID: String, field: String,
    ) -> Bool {
        let lines = content.splitLines()
        return (try? findArrayField(
            in: lines, blockUUID: blockUUID, field: field,
        )) != nil
    }

    private static func insertFieldWithReferences(
        _ content: String,
        blockUUID: String,
        field: String,
        references: [(uuid: String, comment: String)],
    ) throws(EditError) -> String {
        var lines = content.splitLines()
        let (bStart, bEnd) = try findBlock(in: lines, uuid: blockUUID)
        guard let isaIdx = (bStart ... bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("isa = ")
        }) else {
            throw .blockNotFound(uuid: blockUUID)
        }
        let fieldIndent = String(
            lines[isaIdx].prefix(while: { $0 == "\t" || $0 == " " }),
        )
        let entryIndent = fieldIndent + "\t"

        var insert = ["\(fieldIndent)\(field) = ("]
        for ref in references {
            insert.append("\(entryIndent)\(ref.uuid) /* \(ref.comment) */,")
        }
        insert.append("\(fieldIndent));")

        lines.insert(contentsOf: insert, at: isaIdx + 1)
        return lines.joined(separator: "\n")
    }

    private static func detectEntryIndent(
        in lines: [String], blockUUID: String, field: String,
    ) -> String {
        guard let (aStart, aEnd) = try? findArrayField(
            in: lines, blockUUID: blockUUID, field: field,
        ) else {
            return "\t\t\t\t"
        }
        for i in (aStart + 1) ..< aEnd {
            let line = lines[i]
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                return String(
                    line.prefix(while: { $0 == "\t" || $0 == " " }),
                )
            }
        }
        let fieldIndent = String(
            lines[aStart].prefix(while: { $0 == "\t" || $0 == " " }),
        )
        return fieldIndent + "\t"
    }

    private static func extractPlainEntry(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != ");" else { return nil }
        var entry = trimmed.hasSuffix(",")
            ? String(trimmed.dropLast()) : trimmed
        if entry.hasPrefix("\""), entry.hasSuffix("\"") {
            entry = String(entry.dropFirst().dropLast())
        }
        return entry.isEmpty ? nil : entry
    }

    public static func quotePBX(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._/"),
        )
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "\"\(s)\""
    }
}

extension String {
    func splitLines() -> [String] {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
