import MCP
import Foundation

/// Errors raised when a user-supplied value would be unsafe to interpolate into an `NSPredicate`
/// string passed to `log stream` / `log show` (or any other tool that builds predicate strings from
/// user input).
public enum PredicateFilterError: LocalizedError, MCPErrorConvertible {
    case invalidValue(field: String, value: String)
    case unescapableValue(field: String, value: String)

    public var errorDescription: String? {
        switch self {
            case let .invalidValue(field, value):

                "Invalid \(field) '\(value)': only alphanumeric characters, dots, hyphens, and underscores are allowed. Use the explicit 'predicate' parameter for custom filtering."
            case let .unescapableValue(field, value):

                "Invalid \(field) '\(value)': must not be empty or contain newlines or control characters. Use the explicit 'predicate' parameter for custom filtering."
        }
    }

    public func toMCPError() -> MCPError {
        .invalidParams(errorDescription ?? "Invalid filter value")
    }
}

/// Validates user-supplied filter values (bundle identifiers, subsystems, process names, etc.)
/// before they are interpolated into `NSPredicate` strings or `mdfind` queries.
///
/// A value containing quotes or other predicate-syntax characters could otherwise inject arbitrary
/// clauses, leaking logs from unrelated subsystems or breaking the predicate parser. Callers should
/// validate every structured field they interpolate; the explicit `predicate` escape hatch remains
/// available for callers who legitimately need raw predicate syntax.
public enum PredicateFilterValidator {
    /// Allowed characters: ASCII letters, digits, `.`, `-`, `_`. Empty strings are rejected.
    public static func validate(_ value: String, field: String) throws(PredicateFilterError) {
        guard !value.isEmpty else { throw .invalidValue(field: field, value: value) }

        for scalar in value.unicodeScalars {
            switch scalar.value {
                case 0x30...0x39,  // 0-9
                     0x41...0x5A,  // A-Z
                     0x61...0x7A,  // a-z
                     0x2E,         // .
                     0x2D,         // -
                     0x5F:         // _
                    continue
                default: throw .invalidValue(field: field, value: value)
            }
        }
    }

    /// Validates a free-form value (e.g. a process name like `ThesisApp (debug)`) that will be
    /// interpolated into a predicate *string literal* after escaping. Unlike `validate`, this
    /// permits spaces, parentheses, and other punctuation — anything that can be safely placed
    /// inside double quotes once `escapeStringLiteral` runs. Only empty strings, newlines, and
    /// control characters (which can't be escaped into a single-line predicate) are rejected.
    public static func validateStringLiteral(
        _ value: String,
        field: String,
    ) throws(PredicateFilterError) {
        guard !value.isEmpty else { throw .unescapableValue(field: field, value: value) }
        for scalar in value.unicodeScalars
            where scalar.value < 0x20 || scalar.value == 0x7F
            || (0x80...0x9F).contains(scalar.value)
        { throw .unescapableValue(field: field, value: value) }
    }

    /// Escapes a value for safe interpolation inside a double-quoted `NSPredicate` string literal.
    /// Backslashes must be doubled first, then double quotes escaped, so a value like
    /// `He said "hi"` becomes `He said \"hi\"`.
    public static func escapeStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
