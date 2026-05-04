import Foundation

/// Sort string-catalog keys the way Xcode does: `localizedStandardCompare`
/// (natural numeric ordering, case-insensitive) with a lexicographic tiebreak
/// so the result is deterministic across runs.
public enum XCStringsKeySorter {
    public static func sort(_ keys: some Sequence<String>) -> [String] {
        keys.sorted { lhs, rhs in
            let comparison = lhs.localizedStandardCompare(rhs)
            if comparison == .orderedSame {
                return lhs < rhs
            }
            return comparison == .orderedAscending
        }
    }
}
