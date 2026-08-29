import MCP
import XCMCPCore
import XcodeProj
import Foundation

/// Parses and formats the version requirement on an `XCRemoteSwiftPackageReference`.
///
/// `add_swift_package`, `update_swift_package`, `list_swift_packages` and `show_package_resolution`
/// all read or write the same requirement strings, so the mapping between the tool-facing text form
/// and XcodeProj's enum lives here.
public enum PackageRequirement {
    /// Parses a tool-facing requirement string.
    ///
    /// Accepted forms:
    /// - `from: 1.2.0` or `upToNextMajor: 1.2.0` — up to the next major version.
    /// - `upToNextMinor: 1.2.0` — up to the next minor version.
    /// - `exact: 1.2.0` — that version only.
    /// - `range: 1.2.0..<2.0.0` or `range: 1.2.0 - 2.0.0` — a half-open version range.
    /// - `branch: main` — track a branch.
    /// - `revision: <sha>` — pin a raw commit.
    /// - A bare version such as `1.2.0` — that version only.
    public static func parse(
        _ requirement: String
    ) -> XCRemoteSwiftPackageReference.VersionRequirement {
        let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)

        if let value = value(of: "from", in: trimmed) { return .upToNextMajorVersion(value) }

        if let value = value(of: "upToNextMajor", in: trimmed) {
            return .upToNextMajorVersion(value)
        }

        if let value = value(of: "upToNextMinor", in: trimmed) {
            return .upToNextMinorVersion(value)
        }
        if let value = value(of: "branch", in: trimmed) { return .branch(value) }
        if let value = value(of: "revision", in: trimmed) { return .revision(value) }
        if let value = value(of: "exact", in: trimmed) { return .exact(value) }

        if let value = value(of: "range", in: trimmed), let range = parseRange(value) {
            return .range(from: range.from, to: range.to)
        }
        return .exact(trimmed)
    }

    /// Renders a requirement back into the text form ``parse(_:)`` accepts.
    public static func format(
        _ requirement: XCRemoteSwiftPackageReference.VersionRequirement
    ) -> String {
        switch requirement {
            case let .exact(version): "exact: \(version)"
            case let .upToNextMajorVersion(version): "from: \(version)"
            case let .upToNextMinorVersion(version): "upToNextMinor: \(version)"
            case let .range(from, to): "range: \(from)..<\(to)"
            case let .branch(branch): "branch: \(branch)"
            case let .revision(revision): "revision: \(revision)"
        }
    }

    /// Renders the version window a requirement allows, in interval notation. Returns `nil` for a
    /// branch or revision requirement, which has no version window.
    public static func versionWindow(
        _ requirement: XCRemoteSwiftPackageReference.VersionRequirement
    ) -> String? {
        switch requirement {
            case let .exact(version): "== \(version)"
            case let .upToNextMajorVersion(version):
                ">= \(version) < \(SemanticVersion(version)?.nextMajor.description ?? "next major")"
            case let .upToNextMinorVersion(version):
                ">= \(version) < \(SemanticVersion(version)?.nextMinor.description ?? "next minor")"
            case let .range(from, to): ">= \(from) < \(to)"
            case .branch, .revision: nil
        }
    }

    /// The floor a requirement states, or `nil` for a branch or revision requirement.
    ///
    /// A range reports its lower bound, because that is the version a pin sweep raises.
    public static func minimumVersion(
        _ requirement: XCRemoteSwiftPackageReference.VersionRequirement
    ) -> SemanticVersion? {
        switch requirement {
            case let .exact(version): SemanticVersion(version)
            case let .upToNextMajorVersion(version): SemanticVersion(version)
            case let .upToNextMinorVersion(version): SemanticVersion(version)
            case let .range(from, _): SemanticVersion(from)
            case .branch, .revision: nil
        }
    }

    /// The same requirement with its floor moved to `version`, keeping the kind it already had.
    ///
    /// Returns `nil` for a branch or revision requirement, which states no floor to move. A range
    /// keeps its upper bound, so a sweep never widens a window the author chose to close.
    public static func raised(
        _ requirement: XCRemoteSwiftPackageReference.VersionRequirement,
        to version: SemanticVersion,
    ) -> XCRemoteSwiftPackageReference.VersionRequirement? {
        switch requirement {
            case .exact: .exact(version.description)
            case .upToNextMajorVersion: .upToNextMajorVersion(version.description)
            case .upToNextMinorVersion: .upToNextMinorVersion(version.description)
            case let .range(_, to): .range(from: version.description, to: to)
            case .branch, .revision: nil
        }
    }

    /// Reports whether a version falls inside the window a requirement allows. Returns `false` for
    /// a branch or revision requirement, and for a version that does not parse.
    public static func allows(
        _ version: SemanticVersion,
        requirement: XCRemoteSwiftPackageReference.VersionRequirement,
    ) -> Bool {
        switch requirement {
            case let .exact(bound): SemanticVersion(bound) == version
            case let .upToNextMajorVersion(bound):
                SemanticVersion(bound).map { version >= $0 && version < $0.nextMajor } ?? false
            case let .upToNextMinorVersion(bound):
                SemanticVersion(bound).map { version >= $0 && version < $0.nextMinor } ?? false
            case let .range(from, to):
                (SemanticVersion(from).map { version >= $0 } ?? false)
                    && (SemanticVersion(to).map { version < $0 } ?? false)
            case .branch, .revision: false
        }
    }

    // MARK: - Parsing helpers

    /// Returns the text after a `label:` prefix, or `nil` when the prefix is absent.
    private static func value(of label: String, in text: String) -> String? {
        let prefix = label + ":"
        guard text.hasPrefix(prefix) else { return nil }
        return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits `1.2.0..<2.0.0` or `1.2.0 - 2.0.0` into its two bounds.
    private static func parseRange(_ text: String) -> (from: String, to: String)? {
        for separator in ["..<", "...", " - ", "-"] {
            guard let position = text.range(of: separator) else { continue }
            let from = String(text[text.startIndex..<position.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let to = String(text[position.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !from.isEmpty, !to.isEmpty { return (from, to) }
        }
        return nil
    }
}
