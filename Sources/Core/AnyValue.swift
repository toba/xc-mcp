import Foundation

/// One value in a document this server edits without knowing its whole schema
///
/// This is the typed stand-in for `Any` in an Info.plist, a `.xctestplan` and any other file whose
/// keys are open. Such a file carries keys this server never names: a key a newer Xcode writes, and
/// a key the caller passes through an `additional_properties` argument. A fixed `Codable` model
/// would drop every one of them on the next write, so the editors work on this tree instead.
/// Decoding keeps each value's type, so a read followed by a write returns the file unchanged.
///
/// `PropertyListDecoder` and `JSONDecoder` both produce it. The `date` and `data` cases only ever
/// come from a property list, because JSON has no syntax for either.
///
/// ```swift
/// var entry = try PropertyListDecoder().decode([String: AnyValue].self, from: data)
/// entry["CFBundleURLName"] = .string("thesis")
/// let name = entry["CFBundleURLName"]?.stringValue
/// ```
public enum AnyValue: Codable, Sendable, Equatable {
    case string(String)
    case boolean(Bool)
    case integer(Int)
    case double(Double)
    case date(Date)
    case data(Data)
    case array([AnyValue])
    case dictionary([String: AnyValue])

    // MARK: - Reading

    /// The string this value holds, or `nil` when it holds something else.
    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    /// The boolean this value holds, or `nil` when it holds something else.
    ///
    /// A plist distinguishes `<true/>` from `<integer>1</integer>`, so an integer reads as `nil`.
    public var boolValue: Bool? {
        guard case let .boolean(value) = self else { return nil }
        return value
    }

    /// The integer this value holds, or `nil` when it holds something else.
    public var intValue: Int? {
        guard case let .integer(value) = self else { return nil }
        return value
    }

    /// The number this value holds, counting an integer as a number.
    public var doubleValue: Double? {
        switch self {
            case let .double(value): value
            case let .integer(value): Double(value)
            default: nil
        }
    }

    /// The array this value holds, or `nil` when it holds something else.
    public var arrayValue: [AnyValue]? {
        guard case let .array(values) = self else { return nil }
        return values
    }

    /// The dictionary this value holds, or `nil` when it holds something else.
    public var dictionaryValue: [String: AnyValue]? {
        guard case let .dictionary(values) = self else { return nil }
        return values
    }

    /// The dictionaries in the array this value holds, dropping any element that is not one.
    ///
    /// Every nested entry list in an Info.plist and a test plan takes this shape, so reading one
    /// costs a single accessor rather than a map over the elements.
    public var dictionaryArrayValue: [[String: AnyValue]]? {
        guard case let .array(values) = self else { return nil }
        return values.compactMap(\.dictionaryValue)
    }

    /// The strings in the array this value holds, dropping any element that is not a string.
    ///
    /// A lone string reads as a one-element array, because Xcode writes both shapes for a key such
    /// as `public.filename-extension`.
    public var stringArrayValue: [String]? {
        switch self {
            case let .string(value): [value]
            case let .array(values): values.compactMap(\.stringValue)
            default: nil
        }
    }

    /// The value written the way a report prints it.
    public var displayText: String {
        switch self {
            case let .string(value): value
            case let .boolean(value): String(value)
            case let .integer(value): String(value)
            case let .double(value): String(value)
            case let .date(value): value.description
            case let .data(value): "\(value.count) bytes"
            case let .array(values): values.map(\.displayText).joined(separator: ", ")
            case let .dictionary(values):
                values.keys.sorted()
                    .map { "\($0): \(values[$0]?.displayText ?? "")" }
                    .joined(separator: ", ")
        }
    }

    // MARK: - Writing

    /// Wraps a list of strings, which is the shape most Info.plist array keys take.
    public static func strings(_ values: some Sequence<String>) -> AnyValue {
        .array(values.map { .string($0) })
    }

    /// Wraps a list of dictionaries, which is the shape every nested entry list takes.
    public static func dictionaries(_ values: some Sequence<[String: AnyValue]>) -> AnyValue {
        .array(values.map { .dictionary($0) })
    }

    // MARK: - Codable

    /// A coding key for a name no enum can spell, such as `public.mime-type`.
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue _: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var values: [AnyValue] = []
            values.reserveCapacity(container.count ?? 0)
            while !container.isAtEnd { try values.append(container.decode(AnyValue.self)) }
            self = .array(values)
            return
        }

        if let container = try? decoder.container(keyedBy: AnyKey.self) {
            var values: [String: AnyValue] = [:]

            for key in container.allKeys {
                values[key.stringValue] = try container.decode(AnyValue.self, forKey: key)
            }
            self = .dictionary(values)
            return
        }

        let container = try decoder.singleValueContainer()

        // Boolean comes first because a decoder that reads 1 as a boolean would lose the integer.
        // Both PropertyListDecoder and JSONDecoder keep the two apart, so the order holds.
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Date.self) {
            self = .date(value)
        } else if let value = try? container.decode(Data.self) {
            self = .data(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported property list value",
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
            case let .string(value): try encodeSingle(value, to: encoder)
            case let .boolean(value): try encodeSingle(value, to: encoder)
            case let .integer(value): try encodeSingle(value, to: encoder)
            case let .double(value): try encodeSingle(value, to: encoder)
            case let .date(value): try encodeSingle(value, to: encoder)
            case let .data(value): try encodeSingle(value, to: encoder)

            case let .array(values):
                var container = encoder.unkeyedContainer()
                for value in values { try container.encode(value) }

            case let .dictionary(values):
                var container = encoder.container(keyedBy: AnyKey.self)
                for (key, value) in values {
                    try container.encode(value, forKey: AnyKey(stringValue: key))
                }
        }
    }

    private func encodeSingle(_ value: some Encodable, to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// A literal conformance lets a caller write a plist fragment the way the file reads, without a
// wrapping case at every leaf.

extension AnyValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension AnyValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .boolean(value) }
}

extension AnyValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .integer(value) }
}

extension AnyValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension AnyValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnyValue...) { self = .array(elements) }
}

extension AnyValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, AnyValue)...) {
        self = .dictionary(Dictionary(elements) { _, latest in latest })
    }
}
