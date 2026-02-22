import Foundation

/// Extracts `#Preview` block bodies from Swift source code.
///
/// Uses a balanced-brace parser to correctly handle nested braces,
/// string literals, and comments that would trip up regex-based approaches.
///
/// ## Example
///
/// ```swift
/// let source = """
/// #Preview("Dark Mode") {
///     ContentView()
///         .preferredColorScheme(.dark)
/// }
/// """
/// let previews = PreviewExtractor.extractPreviewBodies(from: source)
/// // previews[0].name == "Dark Mode"
/// // previews[0].body == "\n    ContentView()\n        .preferredColorScheme(.dark)\n"
/// ```
public enum PreviewExtractor {
    /// A single extracted preview with optional name and body content.
    public struct Preview: Sendable, Equatable {
        /// The name string from `#Preview("name")`, or nil if unnamed.
        public let name: String?

        /// The body content between the outer braces (excluding the braces themselves).
        public let body: String
    }

    /// Extracts all `#Preview { ... }` blocks from Swift source code.
    ///
    /// - Parameter source: The full Swift source file content.
    /// - Returns: An array of extracted previews in order of appearance.
    public static func extractPreviewBodies(from source: String) -> [Preview] {
        var previews: [Preview] = []
        let chars = Array(source.unicodeScalars)
        let count = chars.count
        var i = 0

        while i < count {
            // Skip string literals
            if chars[i] == "\"" {
                i = skipStringLiteral(chars, from: i)
                continue
            }

            // Skip line comments
            if chars[i] == "/", i + 1 < count, chars[i + 1] == "/" {
                i = skipLineComment(chars, from: i)
                continue
            }

            // Skip block comments
            if chars[i] == "/", i + 1 < count, chars[i + 1] == "*" {
                i = skipBlockComment(chars, from: i)
                continue
            }

            // Look for #Preview
            if chars[i] == "#", matchesPreview(chars, at: i) {
                i += 8  // skip "#Preview"

                // Skip whitespace
                i = skipWhitespace(chars, from: i)

                // Check for optional name: ("...")
                var name: String?
                if i < count, chars[i] == "(" {
                    let (extractedName, newIndex) = extractPreviewName(chars, from: i)
                    name = extractedName
                    i = newIndex
                    i = skipWhitespace(chars, from: i)
                }

                // Expect opening brace
                guard i < count, chars[i] == "{" else {
                    continue
                }

                // Extract body using balanced braces
                let bodyStart = i + 1
                var depth = 1
                var j = bodyStart

                while j < count, depth > 0 {
                    let c = chars[j]

                    if c == "\"" {
                        j = skipStringLiteral(chars, from: j)
                        continue
                    }

                    if c == "/", j + 1 < count, chars[j + 1] == "/" {
                        j = skipLineComment(chars, from: j)
                        continue
                    }

                    if c == "/", j + 1 < count, chars[j + 1] == "*" {
                        j = skipBlockComment(chars, from: j)
                        continue
                    }

                    if c == "{" {
                        depth += 1
                    } else if c == "}" {
                        depth -= 1
                    }

                    if depth > 0 {
                        j += 1
                    }
                }

                if depth == 0 {
                    let bodyScalars = chars[bodyStart..<j]
                    let body = String(String.UnicodeScalarView(bodyScalars))
                    previews.append(Preview(name: name, body: body))
                    i = j + 1
                } else {
                    i = j
                }
            } else {
                i += 1
            }
        }

        return previews
    }

    /// Returns the source with all `#Preview { ... }` blocks removed.
    ///
    /// This is used to preprocess additional source files when compiling them
    /// into the preview host target. Without stripping, the `#Preview` macro
    /// in the original file can trigger a Swift compiler crash (infinite
    /// recursion in ASTMangler when mangling nested closure types in a
    /// different target context).
    public static func stripPreviewBlocks(from source: String) -> String {
        let chars = Array(source.unicodeScalars)
        let count = chars.count
        var result: [Unicode.Scalar] = []
        var i = 0

        while i < count {
            // Skip string literals
            if chars[i] == "\"" {
                let end = skipStringLiteral(chars, from: i)
                result.append(contentsOf: chars[i..<end])
                i = end
                continue
            }

            // Skip line comments
            if chars[i] == "/" && i + 1 < count && chars[i + 1] == "/" {
                let end = skipLineComment(chars, from: i)
                result.append(contentsOf: chars[i..<end])
                i = end
                continue
            }

            // Skip block comments
            if chars[i] == "/" && i + 1 < count && chars[i + 1] == "*" {
                let end = skipBlockComment(chars, from: i)
                result.append(contentsOf: chars[i..<end])
                i = end
                continue
            }

            // Detect #Preview and skip the entire block
            if chars[i] == "#" && matchesPreview(chars, at: i) {
                var j = i + 8  // skip "#Preview"
                j = skipWhitespace(chars, from: j)

                // Skip optional parenthesized arguments
                if j < count && chars[j] == "(" {
                    let (_, afterParen) = extractPreviewName(chars, from: j)
                    j = afterParen
                    j = skipWhitespace(chars, from: j)
                }

                // Skip the brace-balanced body
                if j < count && chars[j] == "{" {
                    var depth = 1
                    j += 1
                    while j < count && depth > 0 {
                        let c = chars[j]
                        if c == "\"" {
                            j = skipStringLiteral(chars, from: j)
                            continue
                        }
                        if c == "/" && j + 1 < count && chars[j + 1] == "/" {
                            j = skipLineComment(chars, from: j)
                            continue
                        }
                        if c == "/" && j + 1 < count && chars[j + 1] == "*" {
                            j = skipBlockComment(chars, from: j)
                            continue
                        }
                        if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }
                        j += 1
                    }
                    // Skip trailing newline after closing brace
                    if j < count && chars[j] == "\n" { j += 1 }
                    i = j
                    continue
                }
            }

            result.append(chars[i])
            i += 1
        }

        return String(String.UnicodeScalarView(result))
    }

    // MARK: - Private Helpers

    /// Checks if `#Preview` keyword starts at the given index.
    private static func matchesPreview(
        _ chars: [Unicode.Scalar], at index: Int
    ) -> Bool {
        let keyword: [Unicode.Scalar] = Array("#Preview".unicodeScalars)
        guard index + keyword.count <= chars.count else { return false }
        for k in 0..<keyword.count where chars[index + k] != keyword[k] {
            return false
        }
        // Must not be followed by an alphanumeric (to avoid matching #PreviewFoo)
        let afterIndex = index + keyword.count
        if afterIndex < chars.count {
            let after = chars[afterIndex]
            if CharacterSet.alphanumerics.contains(after) || after == "_" {
                return false
            }
        }
        return true
    }

    /// Skips whitespace and newlines, returning the new index.
    private static func skipWhitespace(
        _ chars: [Unicode.Scalar], from index: Int
    ) -> Int {
        var i = index
        while i < chars.count && CharacterSet.whitespacesAndNewlines.contains(chars[i]) {
            i += 1
        }
        return i
    }

    /// Skips a string literal (handles multiline `"""` and escaped quotes).
    /// Returns the index after the closing quote.
    private static func skipStringLiteral(
        _ chars: [Unicode.Scalar], from index: Int
    ) -> Int {
        guard index < chars.count && chars[index] == "\"" else { return index + 1 }

        // Check for multiline string literal """
        if index + 2 < chars.count && chars[index + 1] == "\"" && chars[index + 2] == "\"" {
            var i = index + 3
            while i + 2 < chars.count {
                if chars[i] == "\"" && chars[i + 1] == "\"" && chars[i + 2] == "\"" {
                    return i + 3
                }
                if chars[i] == "\\" {
                    i += 2
                } else {
                    i += 1
                }
            }
            return chars.count
        }

        // Single-line string
        var i = index + 1
        while i < chars.count {
            if chars[i] == "\\" {
                i += 2
            } else if chars[i] == "\"" {
                return i + 1
            } else if chars[i] == "\n" {
                // Unterminated string
                return i
            } else {
                i += 1
            }
        }
        return chars.count
    }

    /// Skips a line comment (`//...`), returning the index after the newline.
    private static func skipLineComment(
        _ chars: [Unicode.Scalar], from index: Int
    ) -> Int {
        var i = index + 2
        while i < chars.count && chars[i] != "\n" {
            i += 1
        }
        return i < chars.count ? i + 1 : i
    }

    /// Skips a block comment (`/* ... */`), handling nested block comments.
    /// Returns the index after the closing `*/`.
    private static func skipBlockComment(
        _ chars: [Unicode.Scalar], from index: Int
    ) -> Int {
        var i = index + 2
        var depth = 1
        while i + 1 < chars.count && depth > 0 {
            if chars[i] == "/" && chars[i + 1] == "*" {
                depth += 1
                i += 2
            } else if chars[i] == "*" && chars[i + 1] == "/" {
                depth -= 1
                i += 2
            } else {
                i += 1
            }
        }
        return i
    }

    /// Extracts the preview name from `("name")` syntax.
    /// Returns the name (or nil) and the index after the closing paren.
    private static func extractPreviewName(
        _ chars: [Unicode.Scalar], from index: Int
    ) -> (String?, Int) {
        guard index < chars.count, chars[index] == "(" else {
            return (nil, index)
        }

        var i = index + 1
        i = skipWhitespace(chars, from: i)

        // Look for string literal
        guard i < chars.count, chars[i] == "\"" else {
            // Not a simple name — skip to closing paren
            var depth = 1
            var j = index + 1
            while j < chars.count, depth > 0 {
                if chars[j] == "(" { depth += 1 } else if chars[j] == ")" { depth -= 1 }
                j += 1
            }
            return (nil, j)
        }

        // Extract string content
        let stringStart = i + 1
        i = stringStart
        var nameScalars: [Unicode.Scalar] = []
        while i < chars.count, chars[i] != "\"" {
            if chars[i] == "\\", i + 1 < chars.count {
                nameScalars.append(chars[i + 1])
                i += 2
            } else {
                nameScalars.append(chars[i])
                i += 1
            }
        }

        if i < chars.count { i += 1 }  // skip closing quote

        // Skip to closing paren
        while i < chars.count, chars[i] != ")" {
            i += 1
        }
        if i < chars.count { i += 1 }  // skip closing paren

        let name = String(String.UnicodeScalarView(nameScalars))
        return (name, i)
    }
}
