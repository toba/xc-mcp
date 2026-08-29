import Foundation

/// One `.package(url:)` declaration read from a `Package.swift`
public struct ManifestPin: Sendable, Equatable {
    /// The version form a declaration states
    public enum Requirement: Sendable, Equatable {
        /// `from: "1.2.0"`, the only form ``ManifestPins/rewrite(_:pins:to:)`` edits
        case from(SemanticVersion)

        /// Any other form, named by the keyword that states it
        case other(String)
    }

    /// The repository URL the declaration names
    public let url: String

    /// SwiftPM identity derived from ``url``: the lowercased last path component
    public let identity: String

    public let requirement: Requirement

    /// Character offsets of the version literal's contents, absent unless the form is `from:`
    public let versionOffsets: Range<Int>?

    public init(
        url: String,
        identity: String,
        requirement: Requirement,
        versionOffsets: Range<Int>?,
    ) {
        self.url = url
        self.identity = identity
        self.requirement = requirement
        self.versionOffsets = versionOffsets
    }

    /// The declared floor, or `nil` when the declaration states another form
    public var version: SemanticVersion? {
        guard case let .from(version) = requirement else { return nil }
        return version
    }
}

/// One version floor a rewrite moved
public struct ManifestPinChange: Sendable, Equatable {
    public let identity: String
    public let from: SemanticVersion
    public let to: SemanticVersion

    public init(identity: String, from: SemanticVersion, to: SemanticVersion) {
        self.identity = identity
        self.from = from
        self.to = to
    }

    /// The change as one report token, such as `toba-core 1.12.0 → 1.13.3`
    public var description: String { "\(identity) \(from) → \(to)" }

    /// The change a floor takes, or `nil` when `versions` names no higher version for it.
    ///
    /// Both the manifest rewriter and the Xcode project rewriter decide the same three conditions:
    /// the pin states a floor, the plan names a version for that identity, and the named version
    /// sits above the floor. One copy of the rule keeps a manifest and a project file from
    /// disagreeing about which pins move.
    ///
    /// - Parameters:
    ///   - identity: SwiftPM identity of the pinned package.
    ///   - current: The floor the pin states, absent for a branch or revision requirement.
    ///   - versions: The new floor for each identity to raise, keyed by identity.
    public static func raising(
        _ identity: String,
        from current: SemanticVersion?,
        to versions: [String: SemanticVersion],
    ) -> ManifestPinChange? {
        guard let current, let wanted = versions[identity], wanted > current else { return nil }
        return .init(identity: identity, from: current, to: wanted)
    }
}

/// Reads and rewrites the version floors a `Package.swift` declares
///
/// The scanner works on the manifest text rather than on a decoded manifest, because a rewrite has
/// to leave every other character of the file exactly as it found it. `swift package dump-package`
/// reports the same pins, but it resolves the graph first and it discards the source positions a
/// rewrite needs.
///
/// Two forms sit outside what the scanner reads: a URL or version built at runtime, and a
/// triple-quoted or raw string literal. Neither appears in a dependency list.
public enum ManifestPins {
    /// Everything one pass over a manifest reads
    public struct Reading: Sendable, Equatable {
        /// One pin per `.package(url:)` declaration, in source order
        public let pins: [ManifestPin]

        /// One path per `.package(path:)` declaration, in source order
        public let localPaths: [String]
    }

    /// Reads the pins and the local path dependencies in one pass.
    ///
    /// Call this rather than ``parse(_:)`` and ``localPaths(_:)`` in turn. Each of those builds its
    /// own character mask over the whole file, so two calls scan the manifest twice.
    ///
    /// - Parameter text: The manifest source.
    /// - Returns: Both lists, each in source order.
    public static func read(_ text: String) -> Reading {
        let scan = Scan(text)
        let spans = scan.packageSpans()
        return .init(pins: pins(in: spans, scan: scan), localPaths: paths(in: spans, scan: scan))
    }

    /// Reads every `.package(url:)` declaration in a manifest.
    ///
    /// - Parameter text: The manifest source.
    /// - Returns: One pin per declaration, in source order.
    public static func parse(_ text: String) -> [ManifestPin] {
        let scan = Scan(text)
        return pins(in: scan.packageSpans(), scan: scan)
    }

    /// Reads every `.package(path:)` declaration in a manifest.
    ///
    /// A local path dependency builds the working tree of another repository, so the manifest stops
    /// describing what the code compiles against. A sweep refuses a member that declares one.
    ///
    /// - Parameter text: The manifest source.
    /// - Returns: The declared paths, in source order.
    public static func localPaths(_ text: String) -> [String] {
        let scan = Scan(text)
        return paths(in: scan.packageSpans(), scan: scan)
    }

    /// Reads the pins out of already-located `.package(` spans.
    private static func pins(in spans: [Range<Int>], scan: Scan) -> [ManifestPin] {
        var pins: [ManifestPin] = []

        for span in spans {
            guard let urlToken = scan.token("url:", in: span),
                  let url = scan.stringLiteral(after: urlToken, limit: span.upperBound)
            else { continue }

            let identity = PackageResolvedParser.identity(forURL: url.value)

            if let fromToken = scan.token("from:", in: span),
               let literal = scan.stringLiteral(after: fromToken, limit: span.upperBound),
               let version = SemanticVersion(literal.value)
            {
                pins.append(.init(
                    url: url.value, identity: identity, requirement: .from(version),
                    versionOffsets: literal.offsets,
                ))
                continue
            }

            let keyword = ["exact:", "branch:", "revision:", "range:"]
                .first { scan.token($0, in: span) != nil }
                .map { String($0.dropLast()) }
            pins.append(.init(
                url: url.value, identity: identity, requirement: .other(keyword ?? "unrecognized"),
                versionOffsets: nil,
            ))
        }
        return pins
    }

    /// Reads the local path dependencies out of already-located `.package(` spans.
    private static func paths(in spans: [Range<Int>], scan: Scan) -> [String] {
        spans.compactMap { span in
            guard let token = scan.token("path:", in: span) else { return nil }
            return scan.stringLiteral(after: token, limit: span.upperBound)?.value
        }
    }

    /// The result of a rewrite
    public struct Rewrite: Sendable, Equatable {
        /// The manifest source with each moved floor replaced
        public let text: String

        /// One entry per floor the rewrite moved, in source order
        public let changes: [ManifestPinChange]
    }

    /// Raises the version floors a manifest declares.
    ///
    /// A pin is edited when `versions` names its identity and states a version above the declared
    /// floor. Every other pin, and every other character of the file, is left alone.
    ///
    /// `pins` must come from `text`. ``ManifestPin/versionOffsets`` are character offsets into one
    /// exact string, so a pin read from a different revision of the manifest rewrites the wrong
    /// range. Passing both together is what states that requirement.
    ///
    /// - Parameters:
    ///   - text: The manifest source.
    ///   - pins: The pins read from `text`, as ``read(_:)`` or ``parse(_:)`` returned them.
    ///   - versions: The new floor for each identity to raise, keyed by SwiftPM identity.
    /// - Returns: The rewritten source and the floors that moved.
    public static func rewrite(
        _ text: String,
        pins: [ManifestPin],
        to versions: [String: SemanticVersion],
    ) -> Rewrite {
        var edits: [(offsets: Range<Int>, replacement: String)] = []
        var changes: [ManifestPinChange] = []

        for pin in pins {
            guard let offsets = pin.versionOffsets,
                  let change = ManifestPinChange.raising(
                      pin.identity, from: pin.version, to: versions,
                  ) else { continue }
            edits.append((offsets, change.to.description))
            changes.append(change)
        }
        guard !edits.isEmpty else { return .init(text: text, changes: []) }

        var chars = Array(text)
        // Apply from the end so an earlier edit does not move a later offset.
        for edit in edits.reversed() {
            chars.replaceSubrange(edit.offsets, with: Array(edit.replacement))
        }
        return .init(text: String(chars), changes: changes)
    }

    // MARK: - Scanning

    /// A manifest's characters with a mask marking ordinary code
    ///
    /// Every lookup runs against the mask, so a declaration inside a comment and a label inside a
    /// string literal never match. The mask marks a quote character itself as code and the
    /// characters between a pair of quotes as not code. That is what lets a literal's bounds be
    /// found by scanning for the next code quote.
    struct Scan {
        let chars: [Character]
        let isCode: [Bool]

        init(_ text: String) {
            let chars = Array(text)
            var isCode = [Bool](repeating: true, count: chars.count)
            var inLineComment = false
            var inBlockComment = false
            var inString = false
            var i = 0

            while i < chars.count {
                let c = chars[i]
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

                if inLineComment {
                    isCode[i] = false
                    if c == "\n" { inLineComment = false }
                    i += 1
                } else if inBlockComment {
                    isCode[i] = false

                    if c == "*", next == "/" {
                        isCode[i + 1] = false
                        inBlockComment = false
                        i += 2
                    } else {
                        i += 1
                    }
                } else if inString {
                    if c == "\\", next != nil {
                        isCode[i] = false
                        isCode[i + 1] = false
                        i += 2
                    } else if c == "\"" {
                        inString = false  // the closing quote stays code
                        i += 1
                    } else {
                        isCode[i] = false
                        i += 1
                    }
                } else if c == "/", next == "/" {
                    inLineComment = true
                    isCode[i] = false
                    i += 1
                } else if c == "/", next == "*" {
                    inBlockComment = true
                    isCode[i] = false
                    i += 1
                } else {
                    if c == "\"" { inString = true }
                    i += 1
                }
            }
            self.chars = chars
            self.isCode = isCode
        }

        /// The argument list of each `.package(` call, exclusive of the parentheses.
        func packageSpans() -> [Range<Int>] {
            var spans: [Range<Int>] = []
            var i = 0

            while i < chars.count {
                guard isCode[i],
                      chars[i] == ".",
                      matches(".package", at: i),
                      let open = nextCode(from: i + ".package".count),
                      chars[open] == "("
                else {
                    i += 1
                    continue
                }
                guard let close = matchingParen(from: open) else { break }
                spans.append((open + 1)..<close)
                i = close + 1
            }
            return spans
        }

        /// The offset of the first code occurrence of `token` inside `span`, or `nil`.
        ///
        /// The match must start a word, so `from:` does not match the tail of another label.
        func token(_ token: String, in span: Range<Int>) -> Int? {
            guard token.count <= span.count else { return nil }

            for start in span.lowerBound...(span.upperBound - token.count)
                where matches(token, at: start)
            {
                if start > span.lowerBound, isWordCharacter(chars[start - 1]) { continue }
                return start
            }
            return nil
        }

        /// The next string literal at or after `offset`, bounded by `limit`.
        ///
        /// - Returns: The literal's contents and the offsets those contents occupy.
        func stringLiteral(after offset: Int, limit: Int) -> (value: String, offsets: Range<Int>)? {
            var i = offset

            while i < limit, !(chars[i] == "\"" && isCode[i]) { i += 1 }
            guard i < limit else { return nil }
            let start = i + 1
            var end = start

            while end < limit, !(chars[end] == "\"" && isCode[end]) { end += 1 }
            guard end < limit else { return nil }
            return (String(chars[start..<end]), start..<end)
        }

        // MARK: - Character helpers

        private func matches(_ text: String, at offset: Int) -> Bool {
            let needle = Array(text)
            guard offset + needle.count <= chars.count else { return false }

            for (
                index, character
            ) in needle.enumerated()
                where
                !isCode[offset + index] || chars[offset + index] != character
            { return false }
            return true
        }

        /// The offset of the next code character that is not whitespace.
        private func nextCode(from offset: Int) -> Int? {
            var i = offset

            while i < chars.count, !isCode[i] || chars[i].isWhitespace { i += 1 }
            return i < chars.count ? i : nil
        }

        /// The offset of the parenthesis closing the one at `open`.
        private func matchingParen(from open: Int) -> Int? {
            var depth = 0

            for i in open..<chars.count where isCode[i] {
                if chars[i] == "(" {
                    depth += 1
                } else if chars[i] == ")" {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            return nil
        }

        private func isWordCharacter(_ c: Character) -> Bool {
            c.isLetter || c.isNumber || c == "_"
        }
    }
}
