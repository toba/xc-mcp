import Foundation

/// Surgical text-based editor for pbxproj files.
///
/// XcodeProj's round-trip serializer corrupts unrelated sections (strips comments, adds spurious
/// fields, reformats arrays). These helpers use XcodeProj for reading/validation only, then make
/// targeted text edits to the pbxproj file.
///
/// Two entry points share one implementation:
/// - ``PBXProjEditor`` holds the file as a mutable `[String]` of lines and applies edits in place —
///   use it when a tool chains several edits, so the file is split and re-joined exactly once.
/// - The `static` `String -> String` methods on this enum are thin wrappers over a single-edit
///   ``PBXProjEditor``, kept for callers that apply one edit.
public enum PBXProjTextEditor {
    public enum EditError: Error, CustomStringConvertible {
        case blockNotFound(uuid: String)
        case arrayFieldNotFound(field: String, inBlock: String)
        case sectionNotFound(String)
        case fileNotFound(String)

        public var description: String {
            switch self {
                case let .blockNotFound(uuid): "Block with UUID '\(uuid)' not found in pbxproj"
                case let .arrayFieldNotFound(field, block):
                    "Array field '\(field)' not found in block '\(block)'"
                case let .sectionNotFound(section): "Section '\(section)' not found in pbxproj"
                case let .fileNotFound(path): "File not found: \(path)"
            }
        }
    }

    // MARK: - File I/O

    public static func read(projectPath: String) throws(EditError) -> String {
        let path = PBXProjParsing.pbxprojPath(forProject: projectPath)
        guard let data = FileManager.default.contents(atPath: path),
            let content = String(data: data, encoding: .utf8)
        else {
            throw .fileNotFound(path)
        }
        return content
    }

    /// Read the raw bytes of `project.pbxproj`, for use as the ``write`` concurrency guard
    /// preimage.
    public static func readData(projectPath: String) throws(EditError) -> Data {
        let path = PBXProjParsing.pbxprojPath(forProject: projectPath)
        guard let data = FileManager.default.contents(atPath: path) else {
            throw .fileNotFound(path)
        }
        return data
    }

    /// Durably write the pbxproj text via ``SafeProjectWrite`` (atomic + locked + validated).
    ///
    /// - Parameter expectedPreimage: When provided (the bytes read at load via ``readData``), the
    ///   write is refused if the file changed in the meantime, preserving the concurrent edit.
    public static func write(
        _ content: String,
        projectPath: String,
        expectedPreimage: Data? = nil,
    ) throws {
        let path = PBXProjParsing.pbxprojPath(forProject: projectPath)
        try SafeProjectWrite.write(
            Data(content.utf8),
            to: path,
            lockIdentifier: projectPath,
            expectedPreimage: expectedPreimage,
        )
    }

    // MARK: - Single-edit convenience wrappers

    /// Remove an entire object block (from its UUID line through closing `};`).
    public static func removeBlock(_ content: String, uuid: String) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.removeBlock(uuid: uuid)
        return editor.text
    }

    /// Insert a new `PBXFileSystemSynchronizedBuildFileExceptionSet` block into its section
    /// (creating the section if needed).
    public static func insertExceptionSetBlock(
        _ content: String,
        uuid: String,
        folderName: String,
        targetName: String,
        targetUUID: String,
        membershipExceptions: [String],
    ) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.insertExceptionSetBlock(
            uuid: uuid, folderName: folderName, targetName: targetName,
            targetUUID: targetUUID, membershipExceptions: membershipExceptions,
        )
        return editor.text
    }

    /// Insert a new `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` block into its
    /// section (creating the section if needed).
    public static func insertGroupBuildPhaseMembershipExceptionSetBlock(
        _ content: String,
        uuid: String,
        folderName: String,
        phaseName: String,
        phaseUUID: String,
        phaseComment: String,
        targetName: String,
        membershipExceptions: [String],
    ) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.insertGroupBuildPhaseMembershipExceptionSetBlock(
            uuid: uuid, folderName: folderName, phaseName: phaseName, phaseUUID: phaseUUID,
            phaseComment: phaseComment, targetName: targetName,
            membershipExceptions: membershipExceptions,
        )
        return editor.text
    }

    /// Add plain entries (e.g. filenames) to an existing array field.
    public static func addEntriesToArray(
        _ content: String,
        blockUUID: String,
        field: String,
        entries: [String],
    ) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.addEntriesToArray(blockUUID: blockUUID, field: field, entries: entries)
        return editor.text
    }

    /// Remove plain entries from an array field. Returns modified content and number of entries
    /// remaining.
    public static func removeEntriesFromArray(
        _ content: String,
        blockUUID: String,
        field: String,
        entries: Set<String>,
    ) throws(EditError) -> (content: String, remainingCount: Int) {
        var editor = PBXProjEditor(content)
        let remaining = try editor.removeEntriesFromArray(
            blockUUID: blockUUID, field: field, entries: entries,
        )
        return (editor.text, remaining)
    }

    /// Add a UUID reference to an array field, creating the field if absent.
    public static func addReference(
        _ content: String,
        blockUUID: String,
        field: String,
        refUUID: String,
        comment: String,
    ) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.addReference(
            blockUUID: blockUUID, field: field, refUUID: refUUID, comment: comment,
        )
        return editor.text
    }

    /// Remove a UUID reference from an array field. Removes the entire field if it becomes empty.
    public static func removeReference(
        _ content: String,
        blockUUID: String,
        field: String,
        refUUID: String,
    ) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.removeReference(blockUUID: blockUUID, field: field, refUUID: refUUID)
        return editor.text
    }

    /// Insert block lines into a named section (e.g. "PBXBuildFile"). Creates the section at the
    /// correct alphabetical position if it doesn't exist.
    public static func insertBlockInSection(
        _ content: String,
        section: String,
        blockLines: [String],
    ) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.insertBlockInSection(section: section, blockLines: blockLines)
        return editor.text
    }

    /// Add an array build setting to a configuration, only if the key doesn't already exist.
    public static func addBuildSettingArray(
        _ content: String,
        configUUID: String,
        key: String,
        values: [String],
    ) throws(EditError) -> String {
        var editor = PBXProjEditor(content)
        try editor.addBuildSettingArray(configUUID: configUUID, key: key, values: values)
        return editor.text
    }

    // MARK: - UUID generation

    public static func generateUUID() -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        return .init(unsafeUninitializedCapacity: PBXProjParsing.identifierLength) { buffer in
            for i in 0..<PBXProjParsing.identifierLength { buffer[i] = hex.randomElement()! }
            return PBXProjParsing.identifierLength
        }
    }

    public static func quotePBX(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/"))
        return s.unicodeScalars.allSatisfy { safe.contains($0) } ? s : "\"\(s)\""
    }
}

/// A mutable pbxproj document held as an array of lines.
///
/// Construct once from the file text, apply any number of edits in place, then read ``text`` to
/// serialize. Chaining edits through a single editor splits and re-joins the file exactly once,
/// instead of the O(edits × fileSize) split/join churn of piping the whole `String` through each
/// static ``PBXProjTextEditor`` method.
public struct PBXProjEditor {
    public typealias EditError = PBXProjTextEditor.EditError

    private var lines: [String]

    public init(_ content: String) { lines = content.splitLines() }

    /// The current document serialized back to pbxproj text.
    public var text: String { lines.joined(separator: "\n") }

    // MARK: - Block operations

    /// Remove an entire object block (from its UUID line through closing `};`).
    public mutating func removeBlock(uuid: String) throws(EditError) {
        let (start, end) = try findBlock(uuid: uuid)
        lines.removeSubrange(start...end)
    }

    /// Insert a new `PBXFileSystemSynchronizedBuildFileExceptionSet` block into its section
    /// (creating the section if needed).
    public mutating func insertExceptionSetBlock(
        uuid: String,
        folderName: String,
        targetName: String,
        targetUUID: String,
        membershipExceptions: [String],
    ) throws(EditError) {
        let comment = "Exceptions for \"\(folderName)\" folder in \"\(targetName)\" target"

        var block: [String] = []
        block.append("\t\t\(uuid) /* \(comment) */ = {")
        block.append("\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;")
        block.append("\t\t\tmembershipExceptions = (")
        for file in membershipExceptions {
            block.append("\t\t\t\t\(PBXProjTextEditor.quotePBX(file)),")
        }
        block.append("\t\t\t);")
        block.append("\t\t\ttarget = \(targetUUID) /* \(targetName) */;")
        block.append("\t\t};")

        let sectionEnd = "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */"

        if let idx = lines.firstIndex(where: { $0.contains(sectionEnd) }) {
            lines.insert(contentsOf: block, at: idx)
            return
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
                section.append("/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */")
                section.append(contentsOf: block)
                section.append(sectionEnd)
                lines.insert(contentsOf: section, at: idx)
                return
            }
        }
        throw EditError.sectionNotFound("PBXFileSystemSynchronizedBuildFileExceptionSet")
    }

    /// Insert a new `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` block into its
    /// section (creating the section if needed).
    public mutating func insertGroupBuildPhaseMembershipExceptionSetBlock(
        uuid: String,
        folderName: String,
        phaseName: String,
        phaseUUID: String,
        phaseComment: String,
        targetName: String,
        membershipExceptions: [String],
    ) throws(EditError) {
        let comment =
            "Exceptions for \"\(folderName)\" folder in \"\(phaseName)\" phase from \"\(targetName)\" target"

        var block: [String] = []
        block.append("\t\t\(uuid) /* \(comment) */ = {")
        block.append("\t\t\tisa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet;")
        block.append("\t\t\tbuildPhase = \(phaseUUID) /* \(phaseComment) */;")
        block.append("\t\t\tmembershipExceptions = (")
        for file in membershipExceptions {
            block.append("\t\t\t\t\(PBXProjTextEditor.quotePBX(file)),")
        }
        block.append("\t\t\t);")
        block.append("\t\t};")

        let sectionEnd =
            "/* End PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet section */"

        if let idx = lines.firstIndex(where: { $0.contains(sectionEnd) }) {
            lines.insert(contentsOf: block, at: idx)
            return
        }

        // Section doesn't exist — create it before the next alphabetical section
        let markers = [
            "/* Begin PBXFileSystemSynchronizedRootGroup section */",
            "/* Begin PBXFrameworksBuildPhase section */",
            "/* Begin PBXGroup section */",
        ]

        for marker in markers {
            if let idx = lines.firstIndex(where: { $0.contains(marker) }) {
                var section = [""]
                section.append(
                    "/* Begin PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet section */",
                )
                section.append(contentsOf: block)
                section.append(sectionEnd)
                lines.insert(contentsOf: section, at: idx)
                return
            }
        }
        throw EditError.sectionNotFound(
            "PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet",
        )
    }

    // MARK: - Array entry operations (plain values like filenames)

    /// Add plain entries (e.g. filenames) to an existing array field.
    public mutating func addEntriesToArray(
        blockUUID: String,
        field: String,
        entries: [String],
    ) throws(EditError) {
        let (_, arrayEnd) = try findArrayField(blockUUID: blockUUID, field: field)
        let indent = detectEntryIndent(blockUUID: blockUUID, field: field)

        var newLines: [String] = []
        for entry in entries { newLines.append("\(indent)\(PBXProjTextEditor.quotePBX(entry)),") }
        lines.insert(contentsOf: newLines, at: arrayEnd)
    }

    /// Remove plain entries from an array field. Returns the number of entries remaining.
    public mutating func removeEntriesFromArray(
        blockUUID: String,
        field: String,
        entries: Set<String>,
    ) throws(EditError) -> Int {
        let (arrayStart, arrayEnd) = try findArrayField(blockUUID: blockUUID, field: field)

        var toRemove: [Int] = []

        for i in (arrayStart + 1)..<arrayEnd {
            if let name = Self.extractPlainEntry(lines[i]), entries.contains(name) {
                toRemove.append(i)
            }
        }
        for i in toRemove.reversed() { lines.remove(at: i) }

        let newEnd = arrayEnd - toRemove.count
        var remaining = 0
        for i in (arrayStart + 1)..<newEnd where Self.extractPlainEntry(lines[i]) != nil {
            remaining += 1
        }
        return remaining
    }

    // MARK: - Array reference operations (UUID references with comments)

    /// Add a UUID reference to an array field, creating the field if absent.
    public mutating func addReference(
        blockUUID: String,
        field: String,
        refUUID: String,
        comment: String,
    ) throws(EditError) {
        if hasField(blockUUID: blockUUID, field: field) {
            let (_, arrayEnd) = try findArrayField(blockUUID: blockUUID, field: field)
            let indent = detectEntryIndent(blockUUID: blockUUID, field: field)
            lines.insert("\(indent)\(refUUID) /* \(comment) */,", at: arrayEnd)
            return
        }
        try insertFieldWithReferences(
            blockUUID: blockUUID, field: field, references: [(refUUID, comment)],
        )
    }

    /// Remove a UUID reference from an array field. Removes the entire field if it becomes empty.
    public mutating func removeReference(
        blockUUID: String,
        field: String,
        refUUID: String,
    ) throws(EditError) {
        let (arrayStart, arrayEnd) = try findArrayField(blockUUID: blockUUID, field: field)

        guard let idx = ((arrayStart + 1)..<arrayEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix(refUUID)
        }) else { return }

        lines.remove(at: idx)

        // If array is now empty, remove the entire field
        let newEnd = arrayEnd - 1
        let empty = !((arrayStart + 1)..<newEnd).contains {
            !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        if empty { lines.removeSubrange(arrayStart...newEnd) }
    }

    // MARK: - Section block insertion

    /// Insert block lines into a named section (e.g. "PBXBuildFile"). Creates the section at the
    /// correct alphabetical position if it doesn't exist.
    public mutating func insertBlockInSection(
        section: String,
        blockLines: [String],
    ) throws(EditError) {
        let sectionEnd = "/* End \(section) section */"

        if let idx = lines.firstIndex(where: { $0.contains(sectionEnd) }) {
            lines.insert(contentsOf: blockLines, at: idx)
            return
        }

        // Section doesn't exist — create it at the correct alphabetical position
        var insertionPoint: Int?

        for (i, line) in lines.enumerated() {
            if let beginRange = line.range(of: "/* Begin "),
               let endRange = line.range(of: " section */")
            {
                let existing = String(line[beginRange.upperBound..<endRange.lowerBound])

                if existing > section {
                    insertionPoint = i
                    break
                }
            }
        }

        guard let ip = insertionPoint else { throw EditError.sectionNotFound(section) }

        var newSection = [""]
        newSection.append("/* Begin \(section) section */")
        newSection.append(contentsOf: blockLines)
        newSection.append("/* End \(section) section */")
        lines.insert(contentsOf: newSection, at: ip)
    }

    // MARK: - Build setting operations

    /// Add an array build setting to a configuration, only if the key doesn't already exist.
    public mutating func addBuildSettingArray(
        configUUID: String,
        key: String,
        values: [String],
    ) throws(EditError) {
        let (bStart, bEnd) = try findBlock(uuid: configUUID)

        // Check if key already exists in this block
        for i in bStart...bEnd
            where lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("\(key) ")
        {
            return  // Already set
        }

        // Find buildSettings = { … }; within the block
        guard let settingsStart = (bStart...bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("buildSettings = {")
        }) else {
            throw .arrayFieldNotFound(field: "buildSettings", inBlock: configUUID)
        }

        // Find the closing }; for buildSettings by tracking brace depth
        var depth = 0
        var settingsEnd: Int?

        for i in settingsStart...bEnd {
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
        settingsIndent = settingsStart + 1 < se
            ? Self.leadingIndent(of: lines[settingsStart + 1])
            : "\t\t\t\t"
        let valueIndent = settingsIndent + "\t"

        var insert: [String] = []
        insert.append("\(settingsIndent)\(key) = (")
        for v in values { insert.append("\(valueIndent)\(PBXProjTextEditor.quotePBX(v)),") }
        insert.append("\(settingsIndent));")

        lines.insert(contentsOf: insert, at: se)
    }

    // MARK: - Internals

    private func findBlock(uuid: String) throws(EditError) -> (start: Int, end: Int) {
        // Match block definitions (UUID ... = {) not array references (UUID ... ,)
        guard let start = lines.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return (t.hasPrefix("\(uuid) ") || t.hasPrefix("\(uuid)\t"))
                && t.contains("= {")
        }) else { throw .blockNotFound(uuid: uuid) }
        var depth = 0

        for i in start..<lines.count {
            for c in lines[i] {
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1 }
            }
            if depth == 0 { return (start, i) }
        }
        throw .blockNotFound(uuid: uuid)
    }

    private func findArrayField(
        blockUUID: String,
        field: String,
    ) throws(EditError) -> (start: Int, end: Int) {
        let (bStart, bEnd) = try findBlock(uuid: blockUUID)
        guard let aStart = (bStart...bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces)
                .hasPrefix("\(field) = (")
        }) else { throw .arrayFieldNotFound(field: field, inBlock: blockUUID) }
        guard let aEnd = ((aStart + 1)...bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces) == ");"
        }) else {
            throw .arrayFieldNotFound(field: field, inBlock: blockUUID)
        }
        return (aStart, aEnd)
    }

    private func hasField(blockUUID: String, field: String) -> Bool {
        (try? findArrayField(blockUUID: blockUUID, field: field)) != nil
    }

    private mutating func insertFieldWithReferences(
        blockUUID: String,
        field: String,
        references: [(uuid: String, comment: String)],
    ) throws(EditError) {
        let (bStart, bEnd) = try findBlock(uuid: blockUUID)
        guard let isaIdx = (bStart...bEnd).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("isa = ")
        }) else {
            throw .blockNotFound(uuid: blockUUID)
        }
        let fieldIndent = Self.leadingIndent(of: lines[isaIdx])
        let entryIndent = fieldIndent + "\t"

        var insert = ["\(fieldIndent)\(field) = ("]
        for ref in references { insert.append("\(entryIndent)\(ref.uuid) /* \(ref.comment) */,") }
        insert.append("\(fieldIndent));")

        lines.insert(contentsOf: insert, at: isaIdx + 1)
    }

    private func detectEntryIndent(blockUUID: String, field: String) -> String {
        guard let (aStart, aEnd) = try? findArrayField(blockUUID: blockUUID, field: field) else {
            return "\t\t\t\t"
        }

        for i in (aStart + 1)..<aEnd {
            let line = lines[i]

            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                return Self.leadingIndent(of: line)
            }
        }
        return Self.leadingIndent(of: lines[aStart]) + "\t"
    }

    /// The run of leading tabs/spaces on `line`, used to match the indentation of surrounding
    /// pbxproj entries when inserting new lines.
    private static func leadingIndent(of line: some StringProtocol) -> String {
        String(line.prefix(while: { $0 == "\t" || $0 == " " }))
    }

    private static func extractPlainEntry(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != ");" else { return nil }
        var entry = trimmed.hasSuffix(",")
            ? String(trimmed.dropLast())
            : trimmed
        if entry.hasPrefix("\""), entry.hasSuffix("\"") {
            entry = String(entry.dropFirst().dropLast())
        }
        return entry.isEmpty ? nil : entry
    }
}
