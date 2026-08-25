import Foundation

/// Sort string-catalog keys the way Xcode does: `localizedStandardCompare` (natural numeric
/// ordering, case-insensitive) with a lexicographic tiebreak so the result is deterministic across
/// runs.
public enum XCStringsKeySorter {
    public static func sort(_ keys: some Sequence<String>) -> [String] {
        // bridge each key to NSString once rather than on every comparison the sort makes; the
        // argument side still bridges because localizedStandardCompare takes a String
        let decorated = keys.map { ($0, $0 as NSString) }
        return decorated.sorted { lhs, rhs in
            let comparison = lhs.1.localizedStandardCompare(rhs.0)
            return comparison == .orderedSame
                ? lhs.0 < rhs.0
                : comparison == .orderedAscending
        }.map(\.0)
    }
}
