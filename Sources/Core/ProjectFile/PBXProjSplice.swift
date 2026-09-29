import Foundation

/// Copies an object-level edit into the original `project.pbxproj` text, so a save changes only the
/// object blocks that the edit touched.
///
/// XcodeProj writes the whole file again on each save. Its layout differs from the layout Xcode
/// writes, so a one-target edit shows as a diff of thousands of lines. This type compares two
/// XcodeProj serializations: the project before the edit (the baseline) and the project after the
/// edit (the update). It then applies only the object blocks that differ to the original text.
/// Every other line keeps its original bytes.
///
/// The splice is text-only. The caller must parse the result and confirm that it describes the
/// same project as the update.
public enum PBXProjSplice {
    /// The original text with the object blocks that differ between `baseline` and `updated`
    /// replaced, removed, or inserted.
    ///
    /// - Parameters:
    ///   - original: The project file text on disk.
    ///   - baseline: The XcodeProj serialization of `original`, before the edit.
    ///   - updated: The XcodeProj serialization after the edit.
    /// - Returns: `nil` when a document does not have the expected layout, or when the edit
    ///   changes text outside the `objects` dictionary.
    public static func splice(original: String, baseline: String, updated: String) -> String? {
        guard let source = Document(original),
              let before = Document(baseline),
              let after = Document(updated),
              before.outsideObjects == after.outsideObjects
        else { return nil }

        var removed = Set<String>()
        var replaced = [String: Block]()
        var added = [String: [Block]]()

        for (key, old) in before.blocks {
            guard let new = after.blocks[key] else {
                removed.insert(key)
                continue
            }

            if new.section != old.section {
                removed.insert(key)
                added[new.section, default: []].append(new)
            } else if !before.lines[old.lines].elementsEqual(after.lines[new.lines]) {
                replaced[key] = new
            }
        }

        for (key, new) in after.blocks where before.blocks[key] == nil {
            added[new.section, default: []].append(new)
        }

        if removed.isEmpty, replaced.isEmpty, added.isEmpty { return original }

        // Each edit must find its target in the original, in the section the baseline names.
        for key in removed.union(replaced.keys) {
            guard let block = source.blocks[key], block.section == before.blocks[key]?.section
            else { return nil }
        }

        if added.values.joined().contains(where: {
            source.blocks[$0.key] != nil && !removed.contains($0.key)
        }) {
            return nil
        }

        var edits = [Edit]()

        // A section that loses every block, and gains none, goes away with its markers. The parse
        // refuses any other content between two markers, so the section holds nothing else.
        var emptied = Set<String>()

        for section in source.sections
            where added[section.name] == nil && section.keys.allSatisfy(removed.contains)
        {
            emptied.insert(section.name)
            let blankBefore = section.begin > 0 && source.lines[section.begin - 1].isBlank
            let start = blankBefore ? section.begin - 1 : section.begin
            edits.append(Edit(range: start..<(section.end + 1), lines: []))
        }

        var insertions = [Int: [Substring]]()

        for section in source.sections where !emptied.contains(section.name) {
            for key in section.keys {
                guard let block = source.blocks[key] else { continue }

                if removed.contains(key) {
                    edits.append(Edit(range: block.range, lines: []))
                } else if let new = replaced[key] {
                    edits.append(Edit(range: block.range, lines: Array(after.lines[new.lines])))
                }
            }

            // Xcode sorts the blocks of a section by key, so a new block goes before the first
            // original block with a greater key.
            let incoming = added.removeValue(forKey: section.name) ?? []

            for new in incoming.sorted(by: { $0.key < $1.key }) {
                let index = section.keys.first { $0 > new.key }
                    .flatMap { source.blocks[$0]?.lines.lowerBound } ?? section.end
                insertions[index, default: []].append(contentsOf: after.lines[new.lines])
            }
        }

        // A section the original does not have goes before the first remaining section with a
        // greater name, or at the end of the objects dictionary.
        for name in added.keys.sorted() {
            let blocks = added[name, default: []].sorted { $0.key < $1.key }
            var lines = [Substring("/* Begin \(name) section */")]
            for block in blocks { lines.append(contentsOf: after.lines[block.lines]) }
            lines.append(Substring("/* End \(name) section */"))

            if let next = source.sections.first(where: {
                $0.name > name && !emptied.contains($0.name)
            }) {
                insertions[next.begin, default: []].append(contentsOf: lines + [""])
            } else {
                insertions[source.objectsClose, default: []].append(contentsOf: [""] + lines)
            }
        }

        for (index, lines) in insertions {
            edits.append(Edit(range: index..<index, lines: lines))
        }

        // Apply from the end of the file toward the start so each range stays valid. At one start
        // line, a removal or replacement runs before an insertion, so the insertion lands in front
        // of the line that follows the removed block.
        edits.sort {
            ($0.range.lowerBound, $0.range.upperBound) > ($1.range.lowerBound, $1.range.upperBound)
        }

        var lines = source.lines
        for edit in edits { lines.replaceSubrange(edit.range, with: edit.lines) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Document model

extension PBXProjSplice {
    /// One object entry in the `objects` dictionary.
    struct Block {
        /// The object key, which is its UUID.
        let key: String

        /// The name in the `/* Begin … section */` marker around the block.
        let section: String

        /// The lines the block covers, from the key line through the closing `};`.
        let lines: ClosedRange<Int>

        var range: Range<Int> { lines.lowerBound..<(lines.upperBound + 1) }
    }

    /// One `/* Begin … section */` to `/* End … section */` run.
    struct Section {
        let name: String
        let begin: Int
        let end: Int

        /// The keys of the blocks in the section, in line order.
        let keys: [String]
    }

    /// A line range to replace, and the lines to put in its place.
    struct Edit {
        let range: Range<Int>
        let lines: [Substring]
    }

    /// A `project.pbxproj` text split into lines, with the position of each object block.
    struct Document {
        let lines: [Substring]
        let objectsOpen: Int
        let objectsClose: Int
        let blocks: [String: Block]
        let sections: [Section]

        /// The lines before and after the body of the `objects` dictionary.
        var outsideObjects: [Substring] {
            Array(lines[...objectsOpen]) + lines[objectsClose...]
        }

        /// Parses `text`, or returns `nil` when the text does not have the layout Xcode and
        /// XcodeProj write: one block per object, each inside its section markers.
        init?(_ text: String) {
            // a CR would make the lines of the original differ from the lines of an update
            guard !text.utf8.contains(UInt8(ascii: "\r")) else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

            var depth = 0
            var objectsOpen: Int?
            var objectsClose: Int?
            var blocks = [String: Block]()
            var sections = [Section]()
            var openSection: (name: String, begin: Int, keys: [String])?
            var openBlock: (key: String, line: Int)?

            func record(_ key: String, _ range: ClosedRange<Int>) -> Bool {
                guard let section = openSection, blocks[key] == nil else { return false }
                blocks[key] = Block(key: key, section: section.name, lines: range)
                openSection?.keys.append(key)
                return true
            }

            for (index, line) in lines.enumerated() {
                let start = depth
                guard let end = Self.depth(after: line, from: start) else { return nil }
                depth = end

                guard objectsOpen != nil else {
                    if start == 1, end == 2, line.trimmed.hasPrefix("objects = {") {
                        objectsOpen = index
                    }
                    continue
                }

                if objectsClose != nil { continue }

                if let block = openBlock {
                    if end == 2 {
                        guard record(block.key, block.line...index) else { return nil }
                        openBlock = nil
                    } else if end < 2 {
                        return nil
                    }
                    continue
                }

                if end == 1 {
                    guard openSection == nil else { return nil }
                    objectsClose = index
                    continue
                }

                let trimmed = line.trimmed
                if trimmed.isEmpty { continue }

                if let name = Self.marker(trimmed, "Begin") {
                    guard openSection == nil else { return nil }
                    openSection = (name, index, [])
                    continue
                }

                if let name = Self.marker(trimmed, "End") {
                    guard let section = openSection, section.name == name else { return nil }
                    sections.append(
                        Section(name: name, begin: section.begin, end: index, keys: section.keys),
                    )
                    openSection = nil
                    continue
                }

                guard let key = Self.key(of: trimmed) else { return nil }

                if end == 2 {
                    guard record(key, index...index) else { return nil }
                } else if end > 2 {
                    openBlock = (key, index)
                } else {
                    return nil
                }
            }

            guard let objectsOpen, let objectsClose, depth == 0 else { return nil }
            self.lines = lines
            self.objectsOpen = objectsOpen
            self.objectsClose = objectsClose
            self.blocks = blocks
            self.sections = sections
        }

        /// The name in a `/* Begin NAME section */` or `/* End NAME section */` line.
        private static func marker(_ trimmed: Substring, _ kind: String) -> String? {
            let prefix = "/* \(kind) "
            let suffix = " section */"
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix),
                  trimmed.count > prefix.count + suffix.count
            else { return nil }
            return String(trimmed.dropFirst(prefix.count).dropLast(suffix.count))
        }

        /// The key at the start of an object entry line, without quotes.
        private static func key(of trimmed: Substring) -> String? {
            if trimmed.first == "\"" {
                var key = ""
                var escaped = false

                for character in trimmed.dropFirst() {
                    if escaped {
                        key.append(character)
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        return key.isEmpty ? nil : key
                    } else {
                        key.append(character)
                    }
                }
                return nil
            }

            let key = trimmed.prefix { !$0.isWhitespace && $0 != "=" }
            guard !key.isEmpty, !key.hasPrefix("/") else { return nil }
            return String(key)
        }

        private enum ScanState { case code, string, escape, comment }

        /// The brace depth at the end of `line`, given the depth at its start.
        ///
        /// Braces inside a quoted string or a comment do not count. Returns `nil` when the depth
        /// goes below zero or the line ends inside a string or a block comment. Neither can span
        /// lines in the files Xcode writes.
        private static func depth(after line: Substring, from start: Int) -> Int? {
            var depth = start
            var state = ScanState.code
            var previous: UInt8 = 0

            for byte in line.utf8 {
                switch state {
                    case .string:
                        if byte == UInt8(ascii: "\\") {
                            state = .escape
                        } else if byte == UInt8(ascii: "\"") {
                            state = .code
                        }
                    case .escape:
                        state = .string
                    case .comment:
                        if previous == UInt8(ascii: "*"), byte == UInt8(ascii: "/") {
                            state = .code
                            previous = 0
                            continue
                        }
                    case .code:
                        switch byte {
                            case UInt8(ascii: "\""):
                                state = .string
                            case UInt8(ascii: "*") where previous == UInt8(ascii: "/"):
                                state = .comment
                                previous = 0
                                continue
                            case UInt8(ascii: "/") where previous == UInt8(ascii: "/"):
                                return depth
                            case UInt8(ascii: "{"):
                                depth += 1
                            case UInt8(ascii: "}"):
                                depth -= 1
                                if depth < 0 { return nil }
                            default:
                                break
                        }
                }
                previous = byte
            }
            return state == .code ? depth : nil
        }
    }
}

private extension Substring {
    var trimmed: Substring {
        let start = firstIndex { $0 != "\t" && $0 != " " } ?? endIndex
        let end = lastIndex { $0 != "\t" && $0 != " " }.map(index(after:)) ?? start
        return self[start..<end]
    }

    var isBlank: Bool { allSatisfy { $0 == "\t" || $0 == " " } }
}
