import Foundation

/// Naming utilities for promoting a localizable literal to a manual String Catalog key.
///
/// Xcode 26 auto-generates a camelCased Swift symbol from a `SCREAMING_SNAKE` catalog key (e.g. key
/// `ADD_CITATION_TO_GROUP` → `Text(.addCitationToGroup)`, `RENAME` → `Button(.rename)`). These
/// helpers derive a stable key from a literal and the symbol Xcode would generate, so the caller
/// can preview the resulting call-site form before editing source.
public enum LocalizableKeyNaming {
    /// Derive a `SCREAMING_SNAKE` key from a literal value.
    ///
    /// Format placeholders (`%@`, `%lld`, `%1$(ordinal)@`, …) are stripped first so they don't
    /// pollute the key, then letters/digits are kept (uppercased), every other run of characters
    /// becomes a single `_`, and a leading digit is prefixed with `_` so the generated Swift symbol
    /// stays valid. Returns `"KEY"` for a value with no alphanumeric content. For parameterized
    /// strings, prefer passing an explicit key — the stripped result (e.g. `"Add %@ citation"` →
    /// `ADD_CITATION`) is a reasonable but imperfect default.
    public static func screamingSnakeKey(from value: String) -> String {
        let stripped = stripPlaceholders(from: value)
        var result = ""
        var lastWasUnderscore = false

        for scalar in stripped.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasUnderscore = false
            } else if !lastWasUnderscore, !result.isEmpty {
                result.append("_")
                lastWasUnderscore = true
            }
        }
        if lastWasUnderscore { result.removeLast() }
        result = result.uppercased()
        guard let first = result.first else { return "KEY" }
        return first.isNumber ? "_" + result : result
    }

    /// The full generated member signature for a parameterized value, e.g. key
    /// `ADD_CITATION_TO_GROUP` + value `"Add %1$(ordinal)@ citation"` →
    /// `addCitationToGroup(ordinal: String)`. Returns `nil` when the value has no format
    /// placeholders (the member is a plain property, called as `.symbol`).
    public static func generatedSignature(forKey key: String, value: String) -> String? {
        let params = orderedPlaceholders(in: value)
        guard !params.isEmpty else { return nil }

        let symbol = generatedSymbol(forKey: key)
        let args = params.enumerated().map { index, placeholder -> String in
            if let name = placeholder.name, !name.isEmpty {
                "\(name): \(placeholder.type)"
            } else {
                "_ arg\(index + 1): \(placeholder.type)"
            }
        }
        return "\(symbol)(\(args.joined(separator: ", ")))"
    }

    /// The camelCased Swift symbol Xcode generates from a catalog key, backtick-escaped when it
    /// collides with a Swift keyword (e.g. `IMPORT` → `` `import` ``).
    public static func generatedSymbol(forKey key: String) -> String {
        let components = key
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !components.isEmpty else { return key }

        var symbol = components[0].lowercased()

        for component in components.dropFirst() {
            symbol += component.prefix(1).uppercased() + component.dropFirst().lowercased()
        }

        if symbol.first?.isNumber == true { symbol = "_" + symbol }
        return swiftKeywords.contains(symbol) ? "`\(symbol)`" : symbol
    }

    // MARK: - Format placeholders

    /// One C-style / String Catalog format placeholder parsed from a value.
    struct FormatPlaceholder {
        let position: Int?
        let name: String?
        let type: String
        let start: Int
        let length: Int
    }

    /// Parse format placeholders from a value, in source order. Supports `%@`, `%lld`, positional
    /// `%1$@`, and named `%1$(ordinal)@`. `%%` is treated as a literal escape and ignored.
    static func placeholders(in value: String) -> [FormatPlaceholder] {
        let chars = Array(value)
        let n = chars.count
        var result: [FormatPlaceholder] = []
        var i = 0

        while i < n {
            guard chars[i] == "%" else {
                i += 1
                continue
            }
            let start = i
            var j = i + 1
            guard j < n else { break }

            if chars[j] == "%" {
                i = j + 1
                continue
            }

            // Positional index: digits followed by '$'
            var position: Int?
            var k = j
            var digits = ""

            while k < n, chars[k].isNumber {
                digits.append(chars[k])
                k += 1
            }

            if k < n, chars[k] == "$", !digits.isEmpty {
                position = Int(digits)
                j = k + 1
            }

            // Named argument: '(name)'
            var name: String?

            if j < n, chars[j] == "(" {
                var m = j + 1
                var captured = ""

                while m < n, chars[m] != ")" {
                    captured.append(chars[m])
                    m += 1
                }

                if m < n, chars[m] == ")" {
                    name = captured
                    j = m + 1
                }
            }

            // Length modifiers
            while j < n, "lhLzjtq".contains(chars[j]) { j += 1 }

            guard j < n else { break }
            let conversion = chars[j]
            j += 1

            result.append(FormatPlaceholder(
                position: position, name: name, type: swiftType(forConversion: conversion),
                start: start, length: j - start,
            ))
            i = j
        }
        return result
    }

    /// Placeholders ordered by their positional index (falling back to source order), de-duplicated
    /// by position so `%1$@ ... %1$@` yields a single argument.
    private static func orderedPlaceholders(in value: String) -> [FormatPlaceholder] {
        let found = placeholders(in: value)
        var seenPositions = Set<Int>()
        var ordered: [(sortKey: Int, placeholder: FormatPlaceholder)] = []

        for (index, placeholder) in found.enumerated() {
            if let position = placeholder.position {
                guard seenPositions.insert(position).inserted else { continue }
                ordered.append((position, placeholder))
            } else {
                ordered.append((index + 1, placeholder))
            }
        }
        return ordered.sorted { $0.sortKey < $1.sortKey }.map(\.placeholder)
    }

    /// Remove format placeholder spans from a value (used when deriving a key).
    private static func stripPlaceholders(from value: String) -> String {
        let found = placeholders(in: value)
        guard !found.isEmpty else { return value }

        let chars = Array(value)
        var result = ""
        var index = 0

        for placeholder in found {
            if index < placeholder.start {
                result.append(contentsOf: chars[index..<placeholder.start])
            }
            result.append(" ")
            index = placeholder.start + placeholder.length
        }
        if index < chars.count { result.append(contentsOf: chars[index...]) }
        return result
    }

    /// Map a C format conversion character to the Swift type Xcode generates for the argument.
    private static func swiftType(forConversion conversion: Character) -> String {
        switch conversion {
            case "@", "s", "S": "String"
            case "d", "i", "x", "X", "o": "Int"
            case "u": "UInt"
            case "f", "F", "e", "E", "g", "G", "a", "A": "Double"
            default: "String"
        }
    }

    /// Swift reserved words that require backtick escaping when used as an identifier.
    static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
        "import", "init", "inout", "internal", "let", "open", "operator", "private",
        "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var",
        "break", "case", "continue", "default", "defer", "do", "else", "fallthrough", "for",
        "guard", "if", "in", "repeat", "return", "switch", "where", "while",
        "as", "Any", "catch", "false", "is", "nil", "super", "self", "Self", "throw",
        "throws", "true", "try",
    ]
}
