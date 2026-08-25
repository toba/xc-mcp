import Foundation

/// The module names a failed `swift-symbolgraph-extract` reports as visible
///
/// The compiler answers a module it cannot load with every module the SDK exposes. That list runs
/// past 400 names on macOS, and most of it is clang submodules that no Swift API question reaches.
/// This ranks the list against the requested name and keeps the few closest names.
///
/// ```swift
/// let closest = VisibleModuleList.closest(to: "OrderedCollections", in: result.errorOutput)
/// // ["Collections", "CoreMedia", "Combine", ...]
/// ```
public enum VisibleModuleList {
    /// The line the compiler writes before the names.
    private static let marker = "Current visible modules:"

    /// The most names `closest(to:in:limit:)` returns when the caller names no limit.
    public static let defaultLimit = 10

    /// The shortest candidate that may rank high because the requested name contains it.
    ///
    /// A two-letter name is a substring of half the list, and matching one says nothing about the
    /// module the caller wants.
    private static let shortestContainedCandidate = 4

    /// The names listed under the compiler's visible-modules line.
    ///
    /// - Parameter errorOutput: The stderr of the failed extraction.
    /// - Returns: The names in the order the compiler printed them. Empty when the output carries
    ///   no visible-modules line, which is every failure with another cause.
    public static func parse(_ errorOutput: String) -> [String] {
        guard let range = errorOutput.range(of: marker) else { return [] }
        return errorOutput[range.upperBound...]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The listed names closest to the requested one, best first.
    ///
    /// - Parameters:
    ///   - module: The module the caller asked for.
    ///   - errorOutput: The stderr of the failed extraction.
    ///   - limit: The most names to return.
    /// - Returns: At most `limit` names. Empty when the output carries no visible-modules line.
    public static func closest(
        to module: String,
        in errorOutput: String,
        limit: Int = defaultLimit,
    ) -> [String] { rank(candidates: parse(errorOutput), against: module, limit: limit) }

    /// Orders the candidates by how near each one reads to the requested name.
    static func rank(candidates: [String], against module: String, limit: Int) -> [String] {
        let target = Array(module.lowercased().utf8)
        // an underscored name is a private clang submodule, and it only helps a caller who asked
        // for one
        let keepsUnderscored = module.hasPrefix("_")

        var ranked: [(name: String, tier: Int, distance: Int)] = []
        ranked.reserveCapacity(candidates.count)

        for candidate in candidates where keepsUnderscored || !candidate.hasPrefix("_") {
            let lowered = candidate.lowercased()
            let contains = lowered.contains(module.lowercased())
                || (candidate.count >= shortestContainedCandidate
                    && module.lowercased().contains(lowered))
            ranked.append((candidate, contains ? 0 : 1, editDistance(Array(lowered.utf8), target)))
        }

        ranked.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            return $0.distance != $1.distance
                ? $0.distance < $1.distance
                : $0.name < $1.name
        }
        return ranked.prefix(limit).map(\.name)
    }

    /// The Levenshtein distance between two byte sequences, over one row of state.
    private static func editDistance(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var row = Array(0...rhs.count)

        for (i, left) in lhs.enumerated() {
            var diagonal = row[0]
            row[0] = i + 1

            for (j, right) in rhs.enumerated() {
                let candidate = min(row[j] + 1, row[j + 1] + 1, diagonal + (left == right ? 0 : 1))
                diagonal = row[j + 1]
                row[j + 1] = candidate
            }
        }
        return row[rhs.count]
    }
}
