/// Sort string-catalog keys the way Xcode's `xcstringstool` does: by UTF-8 byte order.
///
/// The order is not natural numeric order, and it is not `String <`. `String <` compares
/// canonically equivalent strings as equal, but `xcstringstool` compares the bytes. Byte order is
/// a total order on distinct keys, so the result is deterministic across runs.
public enum XCStringsKeySorter {
    public static func sort(_ keys: some Sequence<String>) -> [String] {
        keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// Sort the entries of a dictionary keyed by string-catalog key, in the same order as `sort`.
    /// Use it in place of `sort(dictionary.keys)` plus a second lookup for each key.
    public static func sortedEntries<Value>(
        _ dictionary: [String: Value]
    ) -> [(key: String, value: Value)] {
        dictionary.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
    }
}
