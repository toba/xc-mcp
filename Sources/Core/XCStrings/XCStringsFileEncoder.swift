import Foundation

/// Encodes an `XCStringsFile` in the on-disk format that Xcode's `xcstringstool` writes: top-level
/// `sourceLanguage` / `strings` / `version` order, every other object key in UTF-8 byte order,
/// `"key" : value` with a space before the colon, an empty object as an open brace, a blank line
/// and a close brace, no empty `localizations` object, and no trailing newline.
///
/// This matches the output of Ryu0118/xcstrings-crud@78b31d0 so a round trip through this encoder
/// produces a zero-diff against an Xcode-saved catalog.
public enum XCStringsFileEncoder {
    public static func encode(_ file: XCStringsFile) throws -> Data {
        let strings = try XCStringsKeySorter.sortedEntries(file.strings).map { key, entry in
            var entry = entry
            // xcstringstool leaves out an empty localizations object, as it does a nil one. A
            // delete of a key's last language leaves one behind.
            if entry.localizations?.isEmpty == true { entry.localizations = nil }
            return try JSONMember(key: key, value: encodeJSONValue(entry))
        }

        let root = JSONValue.object([
            JSONMember(key: "sourceLanguage", value: .string(file.sourceLanguage)),
            JSONMember(key: "strings", value: .object(strings)),
            JSONMember(key: "version", value: .string(file.version)),
        ])

        // xcstringstool writes no trailing newline
        return Data(root.render().utf8)
    }

    /// Shared because a catalog builds one JSON value per entry, and a 3000-key catalog would
    /// otherwise construct 3000 encoders per save. It sorts no keys, because `JSONValue` re-sorts
    /// every object in byte order.
    private static let entryEncoder = JSONEncoder()

    private static func encodeJSONValue(_ value: some Encodable) throws -> JSONValue {
        let data = try entryEncoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue(jsonObject: object)
    }
}

private struct JSONMember {
    let key: String
    let value: JSONValue
}

private enum JSONValue {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    init(jsonObject: Any) throws {
        switch jsonObject {
            case let object as [String: Any]:
                self = try .object(
                    XCStringsKeySorter.sort(object.keys).map { key in
                        try JSONMember(key: key, value: JSONValue(jsonObject: object[key] as Any))
                    })
            case let array as [Any]: self = try .array(array.map { try JSONValue(jsonObject: $0) })
            case let string as String: self = .string(string)
            case let number as NSNumber:
                // NSNumber bridges both Bool and numeric — disambiguate via CFTypeID.
                self = CFGetTypeID(number) == CFBooleanGetTypeID()
                    ? .bool(number.boolValue)
                    : .number(number.stringValue)
            case _ as NSNull: self = .null
            default:
                throw EncodingError.invalidValue(
                    jsonObject,
                    EncodingError.Context(
                        codingPath: [],
                        debugDescription: "Unsupported JSON value \(jsonObject)"
                    )
                )
        }
    }

    func render(indentation: Int = 0) -> String {
        switch self {
            case let .object(members):
                // xcstringstool writes an empty object as an open brace, a blank line, and a close
                // brace at the object's own indentation
                guard !members.isEmpty else { return "{\n\n\(String.spaces(indentation))}" }
                let childIndentation = indentation + 2
                let lines = members.map { member in
                    "\(String.spaces(childIndentation))\(member.key.jsonEscaped()) : \(member.value.render(indentation: childIndentation))"
                }
                return "{\n\(lines.joined(separator: ",\n"))\n\(String.spaces(indentation))}"
            case let .array(values):
                guard !values.isEmpty else { return "[]" }
                let childIndentation = indentation + 2
                let lines = values.map { value in
                    "\(String.spaces(childIndentation))\(value.render(indentation: childIndentation))"
                }
                return "[\n\(lines.joined(separator: ",\n"))\n\(String.spaces(indentation))]"
            case let .string(string): return string.jsonEscaped()
            case let .number(number): return number
            case let .bool(bool): return bool ? "true" : "false"
            case .null: return "null"
        }
    }
}

fileprivate extension String {
    static func spaces(_ count: Int) -> String { .init(repeating: " ", count: count) }

    /// Renders the string as a JSON string literal, quotes included.
    ///
    /// Written out rather than delegated to a `JSONEncoder`, which the renderer would otherwise
    /// construct once per key and once per value. A slash stays unescaped to mirror Xcode's on-disk
    /// format: it is valid JSON either way, and the escaped form produces noisy diffs against
    /// catalogs holding strings like "Domestic / Foreign". Only a quote, a backslash and the
    /// control range need a substitution; everything above it goes through untouched, including
    /// non-ASCII, which is what JSONEncoder does by default.
    func jsonEscaped() -> String {
        var escaped = "\""
        escaped.reserveCapacity(count + 2)

        for scalar in unicodeScalars {
            switch scalar {
                case "\"": escaped += #"\""#
                case "\\": escaped += #"\\"#
                case "\n": escaped += #"\n"#
                case "\r": escaped += #"\r"#
                case "\t": escaped += #"\t"#
                case "\u{08}": escaped += #"\b"#
                case "\u{0C}": escaped += #"\f"#
                case _ where scalar.value < 0x20:
                    escaped += String(format: #"\u%04x"#, scalar.value)
                default: escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped + "\""
    }
}
