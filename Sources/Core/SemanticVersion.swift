import Foundation

/// A semantic version, parsed from a git tag or a SwiftPM version string.
///
/// Comparison follows the semver precedence rules: major, then minor, then patch, then prerelease.
/// A version with a prerelease identifier sorts before the same version without one. Build metadata
/// is kept for display and ignored for comparison.
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Dot-separated prerelease identifiers, empty when the version is a final release.
    public let prerelease: [String]
    /// Build metadata after `+`, ignored for ordering.
    public let build: String?

    public init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: [String] = [],
        build: String? = nil,
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    /// Parses a version string. Accepts an optional leading `v`, and a one-, two- or
    /// three-component core such as `2`, `2.1` or `2.1.0`. Returns `nil` when the core does not
    /// parse.
    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("v") || body.hasPrefix("V") { body.removeFirst() }
        guard !body.isEmpty else { return nil }

        var build: String?

        if let plus = body.firstIndex(of: "+") {
            build = String(body[body.index(after: plus)...])
            body = String(body[body.startIndex..<plus])
        }

        var prerelease: [String] = []

        if let hyphen = body.firstIndex(of: "-") {
            prerelease = String(body[body.index(after: hyphen)...]).split(separator: ".")
                .map(String.init)
            body = String(body[body.startIndex..<hyphen])
        }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        numbers.reserveCapacity(3)

        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }

        self.init(
            major: numbers[0], minor: numbers[1], patch: numbers[2],
            prerelease: prerelease, build: build,
        )
    }

    /// The exclusive upper bound of an `upToNextMajor` requirement anchored at this version.
    public var nextMajor: SemanticVersion { .init(major: major + 1, minor: 0, patch: 0) }

    /// The exclusive upper bound of an `upToNextMinor` requirement anchored at this version.
    public var nextMinor: SemanticVersion { .init(major: major, minor: minor + 1, patch: 0) }

    /// Reports whether the version carries a prerelease identifier such as `2.0.0-beta.1`.
    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        var text = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty { text += "-" + prerelease.joined(separator: ".") }
        if let build { text += "+" + build }
        return text
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major != rhs.major
            ? lhs.major < rhs.major
            : lhs.minor != rhs.minor
                ? lhs.minor < rhs.minor
                : lhs.patch != rhs.patch
                    ? lhs.patch < rhs.patch
                    : lhs.prerelease.isEmpty || rhs.prerelease.isEmpty
                        ? !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
                        : comparePrerelease(lhs.prerelease, rhs.prerelease)
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    /// Compares prerelease identifier lists. A numeric identifier ranks below an alphanumeric one,
    /// and a shorter list ranks below a longer list that shares its prefix.
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) {
            if left == right { continue }
            let leftNumber = Int(left)
            let rightNumber = Int(right)

            switch (leftNumber, rightNumber) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return left < right
            }
        }
        return lhs.count < rhs.count
    }
}
