import MCP
import TobaCore
import Foundation

/// The trait set a `swift build` or `swift test` invocation enables.
///
/// A trait is a named build configuration a package declares in its `Package.swift` file. SwiftPM
/// enables the package's default traits when the command names none, so a trait declared with no
/// default never reaches the compiler. Source behind `#if <TraitName>` and a dependency gated with
/// `condition: .when(traits: [...])` both stay out of the build, and the command still reports
/// success.
///
/// ## Example
///
/// ```swift
/// let traits = try SwiftBuildTraits.parse(from: arguments) ?? .packageDefault
/// let args = SwiftRunner.buildArguments(traits: traits)
/// ```
public enum SwiftBuildTraits: Sendable, Equatable {
    /// The package's own default trait set, which is what SwiftPM uses when a command names none.
    case packageDefault

    /// An explicit list of traits, passed to `--traits`.
    case named([String])

    /// Every trait the package declares, passed as `--enable-all-traits`.
    case all

    /// The token that puts the package default traits back into an explicit `--traits` list.
    ///
    /// SwiftPM replaces the default set rather than adding to it, so a list that omits this token
    /// builds with the named traits alone.
    public static let defaultsToken = "defaults"

    /// The SwiftPM flags that select this trait set.
    public var arguments: [String] {
        switch self {
            case .packageDefault: []
            case let .named(traits):
                traits.isEmpty
                    ? []
                    : ["--traits", traits.joined(separator: ",")]
            case .all: ["--enable-all-traits"]
        }
    }

    /// A label for a tool result, such as `traits defaults, DataTesting`.
    ///
    /// Never empty. A result that omits the trait set reads as full coverage when the run skipped
    /// every trait-gated source file.
    public var label: String {
        switch self {
            case .packageDefault: "default traits"
            case let .named(traits):
                traits.isEmpty ? "default traits" : "traits \(traits.joined(separator: ", "))"
            case .all: "all traits"
        }
    }

    /// The sentence a result adds when the named list drops the package default traits.
    ///
    /// - Returns: `nil` when the trait set keeps the defaults, so nothing is at risk.
    public var replacedDefaultsWarning: String? {
        guard case let .named(traits) = self,
              !traits.isEmpty,
              !traits.contains(Self.defaultsToken) else { return nil }
        return
            "`--traits` replaces the package default trait set rather than adding to it, so this run "
            + "built none of the default traits. Add \"\(Self.defaultsToken)\" to `traits` to keep them."
    }

    /// Parses the `traits` and `enable_all_traits` tool arguments.
    ///
    /// Presence of either key is an explicit choice, so `traits: []` and `enable_all_traits: false`
    /// both select ``packageDefault`` and thereby suppress a session default for one call.
    ///
    /// - Parameter arguments: The tool call arguments.
    /// - Returns: The requested trait set, or `nil` when the caller passes neither key.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the call carries both keys, which name two
    ///   different trait sets.
    public static func parse(
        from arguments: [String: Value],
    ) throws(MCPError) -> SwiftBuildTraits? {
        let hasTraits = if case .array = arguments["traits"] { true } else { false }
        let hasEnableAll = if case .bool = arguments["enable_all_traits"] { true } else { false }

        if hasTraits, hasEnableAll {
            throw .invalidParams(
                "`traits` and `enable_all_traits` name two different trait sets, so a call cannot "
                    + "carry both. Pass `enable_all_traits: true` to build every declared trait, or "
                    + "pass `traits` to name the ones you want.",
            )
        }
        if hasEnableAll { return arguments.getBool("enable_all_traits") ? .all : .packageDefault }
        guard hasTraits else { return nil }
        let named = arguments.getStringArray("traits").uniqued()
        return named.isEmpty ? .packageDefault : .named(named)
    }

    /// The JSON-schema properties every tool that selects a trait set declares.
    public static let schemaProperties: [String: Value] = [
        "traits": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(
                "Package traits to enable, one --traits list. A trait declared with no default is otherwise never compiled: its #if <Trait> source and its trait-gated dependencies stay out of the build and the run still reports success. --traits replaces the package default set, so add \"defaults\" to keep it, e.g. [\"defaults\", \"DataTesting\"]. Pass an empty array to use the package defaults. swiftc_flags is not a substitute: -DTrait sets the compilation condition and leaves the manifest dependency condition off, so every gated file fails on a missing module.",
            ),
        ]),
        "enable_all_traits": .object([
            "type": .string("boolean"),
            "description": .string(
                "Enable every trait the package declares (--enable-all-traits). Mutually exclusive with traits.",
            ),
        ]),
    ]
}
