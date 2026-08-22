import MCP
import TobaCore
import XCMCPCore
import XcodeProj

/// Shared handling of SwiftPM package traits on Swift Package references.
///
/// A trait is a named build configuration that a package declares in its `Package.swift` file.
/// Xcode 26.4 and later store the enabled traits on the package reference in the project file. An
/// earlier Xcode version ignores the key.
enum SwiftPackageTraits {
    /// Schema property for the optional `traits` argument.
    static var schemaProperty: [String: Value] {
        [
            "traits": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Package traits to enable on the package reference (Xcode 26.4+). "
                        + "A trait is a named build configuration declared by the package. "
                        + "Pass an empty array to clear the traits. "
                        + "Omit the argument to leave the traits unchanged.",
                ),
            ])
        ]
    }

    /// Reads the `traits` argument.
    ///
    /// - Returns: The requested traits, or `nil` when the caller omits the argument. An empty array
    ///   means the caller wants to clear the traits.
    static func parse(from arguments: [String: Value]) -> [String]? {
        guard case .array = arguments["traits"] else { return nil }
        return arguments.getStringArray("traits").uniqued()
    }

    /// Converts parsed traits to the value stored on a package reference.
    ///
    /// An empty list maps to `nil` so the writer omits the key.
    static func stored(_ traits: [String]?) -> [String]? {
        guard let traits, !traits.isEmpty else { return nil }
        return traits
    }

    /// Formats traits as a suffix for tool output.
    ///
    /// - Returns: An empty string when the reference has no traits.
    static func format(_ traits: [String]?) -> String {
        guard let traits, !traits.isEmpty else { return "" }
        return " [traits: \(traits.joined(separator: ", "))]"
    }

    /// Describes a traits change for a result message.
    static func changeDescription(_ traits: [String]) -> String {
        traits.isEmpty
            ? " (cleared package traits)"
            : " (enabled package traits: \(traits.joined(separator: ", ")))"
    }
}
