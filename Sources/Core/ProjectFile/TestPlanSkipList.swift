import Foundation

/// Reads and edits a test plan `skippedTests` value in either shape Xcode writes.
///
/// Xcode writes two shapes for the same key. The flat shape is an array of identifier strings, such
/// as `["PerfTests", "PerfTests/testDecode()"]`. The structured shape is a dictionary with a
/// `suites` array for Swift Testing and an `xctestClasses` array for XCTest. A suite node holds a
/// `name`, an optional nested `suites` array, and an optional `testFunctions` array. A class node
/// holds a `name` and an optional `xctestMethods` array.
///
/// Every function here edits the value in place and keeps unknown keys. That keeps a plan written
/// by a newer Xcode lossless through a round trip. The type therefore works on the raw
/// `[String: Any]` that `JSONSerialization` produces instead of a decoded model.
public enum TestPlanSkipList {
    /// The shape of the value that was read, with the counts that describe it.
    public enum Shape: Equatable, Sendable {
        /// The array shape, with the identifiers it holds.
        case flat([String])
        /// The dictionary shape, with the number of top-level suites and classes.
        case structured(suiteCount: Int, classCount: Int)
        /// The key is absent.
        case absent
    }

    /// The result of an add or a remove.
    public struct Outcome {
        /// The new value for the key. A `nil` value means the caller removes the key.
        public var value: Any?
        /// The shape of the new value.
        public var shape: Shape
        /// The number of leaf entries before the change.
        public var entriesBefore: Int
        /// The number of leaf entries after the change.
        public var entriesAfter: Int
        /// The identifiers that matched nothing. A remove reports these.
        public var unmatched: [String]
        /// The identifiers that were already present. An add reports these.
        public var alreadyPresent: [String]
    }

    // MARK: - Entry points

    /// Adds identifiers to a `skippedTests` value.
    ///
    /// An absent value or a flat value produces a flat value. A structured value stays structured.
    /// An identifier whose first segment names an existing XCTest class goes to `xctestClasses`.
    /// Every other identifier goes to `suites`.
    public static func adding(_ identifiers: [String], to value: Any?) -> Outcome {
        let before = entryCount(of: value)

        if var dict = value as? [String: Any] {
            var alreadyPresent: [String] = []

            for identifier in identifiers {
                let didAdd = addToStructured(identifier, in: &dict)
                if !didAdd { alreadyPresent.append(identifier) }
            }
            return makeOutcome(
                dict, before: before, unmatched: EmptyCollection<String>(),
                alreadyPresent: alreadyPresent)
        }

        let existing = value as? [String] ?? []
        let existingSet = Set(existing)
        let alreadyPresent = identifiers.filter { existingSet.contains($0) }
        var result = existing
        var added = Set<String>()

        for identifier in identifiers where !existingSet.contains(identifier) {
            guard added.insert(identifier).inserted else { continue }
            result.append(identifier)
        }
        return makeOutcome(
            result, before: before, unmatched: EmptyCollection<String>(),
            alreadyPresent: alreadyPresent)
    }

    /// Removes identifiers from a `skippedTests` value.
    ///
    /// A structured value keeps every entry the identifiers do not name. The value drops to `nil`
    /// only when the removal leaves no entries at all.
    public static func removing(_ identifiers: [String], from value: Any?) -> Outcome {
        let before = entryCount(of: value)

        if var dict = value as? [String: Any] {
            var unmatched: [String] = []

            for identifier in identifiers {
                let didRemove = removeFromStructured(identifier, in: &dict)
                if !didRemove { unmatched.append(identifier) }
            }
            return makeOutcome(
                dict, before: before, unmatched: unmatched,
                alreadyPresent: EmptyCollection<String>())
        }

        let existing = value as? [String] ?? []
        let existingSet = Set(existing)
        let unmatched = identifiers.filter { !existingSet.contains($0) }
        let removeSet = Set(identifiers)
        let result = existing.filter { !removeSet.contains($0) }
        return makeOutcome(
            result, before: before, unmatched: unmatched, alreadyPresent: EmptyCollection<String>())
    }

    // MARK: - Counting

    /// Counts the leaf entries a `skippedTests` value holds.
    ///
    /// A suite named with no children counts as one entry, because it skips everything under
    /// itself. A suite with children counts its children instead.
    public static func entryCount(of value: Any?) -> Int {
        if let list = value as? [String] { return list.count }
        guard let dict = value as? [String: Any] else { return 0 }
        let suites: [[String: Any]] = array(forKey: "suites", in: dict)
        let classes: [[String: Any]] = array(forKey: "xctestClasses", in: dict)
        return suites.reduce(0) { $0 + suiteEntryCount($1) }
            + classes.reduce(0) { $0 + classEntryCount($1) }
    }

    private static func suiteEntryCount(_ node: [String: Any]) -> Int {
        let children: [[String: Any]] = array(forKey: "suites", in: node)
        let functions: [String] = array(forKey: "testFunctions", in: node)
        let total = children.reduce(0) { $0 + suiteEntryCount($1) } + functions.count
        return total == 0 ? 1 : total
    }

    private static func classEntryCount(_ node: [String: Any]) -> Int {
        let methods: [String] = array(forKey: "xctestMethods", in: node)
        return methods.isEmpty ? 1 : methods.count
    }

    // MARK: - Outcome

    private static func shape(of value: Any?) -> Shape {
        if let list = value as? [String] { return .flat(list) }
        guard let dict = value as? [String: Any] else { return .absent }
        let suites: [[String: Any]] = array(forKey: "suites", in: dict)
        let classes: [[String: Any]] = array(forKey: "xctestClasses", in: dict)
        return .structured(suiteCount: suites.count, classCount: classes.count)
    }

    /// Wraps a new value in an outcome and drops it to `nil` when it holds nothing.
    private static func makeOutcome(
        _ value: Any,
        before: Int,
        unmatched: some Sequence<String>,
        alreadyPresent: some Sequence<String>,
    ) -> Outcome {
        let pruned = isEmptyValue(value) ? nil : value
        return .init(
            value: pruned,
            shape: shape(of: pruned),
            entriesBefore: before,
            entriesAfter: entryCount(of: pruned),
            unmatched: Array(unmatched),
            alreadyPresent: Array(alreadyPresent),
        )
    }

    /// Reports whether a value holds no skip entries.
    ///
    /// A structured value with other keys stays, because those keys carry data this type does not
    /// model.
    private static func isEmptyValue(_ value: Any) -> Bool {
        if let list = value as? [String] { return list.isEmpty }
        guard let dict = value as? [String: Any] else { return true }
        let hasOtherKeys = dict.keys.contains { $0 != "suites" && $0 != "xctestClasses" }
        return !hasOtherKeys && entryCount(of: dict) == 0
    }

    // MARK: - Structured remove

    /// Removes one identifier from a structured value. Returns `true` when it matched.
    private static func removeFromStructured(
        _ identifier: String,
        in dict: inout [String: Any],
    ) -> Bool {
        let path = segments(of: identifier)
        guard !path.isEmpty else { return false }

        var suites: [[String: Any]] = array(forKey: "suites", in: dict)

        if removeFromSuites(path[...], in: &suites) {
            setOrRemove(suites, forKey: "suites", in: &dict)
            return true
        }

        var classes: [[String: Any]] = array(forKey: "xctestClasses", in: dict)

        if removeFromClasses(path, in: &classes) {
            setOrRemove(classes, forKey: "xctestClasses", in: &dict)
            return true
        }

        return false
    }

    /// Removes one path from a suite array. Returns `true` when it matched.
    private static func removeFromSuites(
        _ path: ArraySlice<String>,
        in suites: inout [[String: Any]],
    ) -> Bool {
        guard let head = path.first else { return false }
        let rest = path.dropFirst()

        guard let index = suites.firstIndex(where: { $0["name"] as? String == head }) else {
            return false
        }

        if rest.isEmpty {
            suites.remove(at: index)
            return true
        }

        var node = suites[index]
        var matched = false
        var children: [[String: Any]] = array(forKey: "suites", in: node)

        if removeFromSuites(rest, in: &children) {
            matched = true
            setOrRemove(children, forKey: "suites", in: &node)
        }

        if !matched, rest.count == 1, let leaf = rest.first {
            var functions: [String] = array(forKey: "testFunctions", in: node)

            if let position = functions.firstIndex(where: { functionName($0, matches: leaf) }) {
                functions.remove(at: position)
                matched = true
                setOrRemove(functions, forKey: "testFunctions", in: &node)
            }
        }

        guard matched else { return false }

        // A node left with no children would skip its whole suite, which inverts the caller's
        // intent. Drop the node instead.
        if isWholeSuite(node) { suites.remove(at: index) } else { suites[index] = node }
        return true
    }

    /// Removes one path from an XCTest class array. Returns `true` when it matched.
    private static func removeFromClasses(
        _ path: [String],
        in classes: inout [[String: Any]],
    ) -> Bool {
        guard path.count <= 2, let head = path.first else { return false }
        guard let index = classes.firstIndex(where: { $0["name"] as? String == head }) else {
            return false
        }

        if path.count == 1 {
            classes.remove(at: index)
            return true
        }

        var node = classes[index]
        var methods: [String] = array(forKey: "xctestMethods", in: node)
        guard let position = methods.firstIndex(where: { functionName($0, matches: path[1]) })
        else { return false }
        methods.remove(at: position)

        if methods.isEmpty {
            classes.remove(at: index)
        } else {
            node["xctestMethods"] = methods
            classes[index] = node
        }
        return true
    }

    // MARK: - Structured add

    /// Adds one identifier to a structured value. Returns `false` when it was already there.
    private static func addToStructured(
        _ identifier: String,
        in dict: inout [String: Any],
    ) -> Bool {
        let path = segments(of: identifier)
        guard let head = path.first else { return false }

        var classes: [[String: Any]] = array(forKey: "xctestClasses", in: dict)

        if classes.contains(where: { $0["name"] as? String == head }) {
            guard addToClasses(path, in: &classes) else { return false }
            dict["xctestClasses"] = classes
            return true
        }

        var suites: [[String: Any]] = array(forKey: "suites", in: dict)
        guard addToSuites(path[...], in: &suites) else { return false }
        dict["suites"] = suites
        return true
    }

    /// Adds one path to a suite array. Returns `false` when the path is already covered.
    private static func addToSuites(
        _ path: ArraySlice<String>,
        in suites: inout [[String: Any]],
    ) -> Bool {
        guard let head = path.first else { return false }
        let rest = path.dropFirst()
        let index = suites.firstIndex { $0["name"] as? String == head }

        // A leaf path names a whole suite. It replaces any narrower entry under that name.
        if rest.isEmpty {
            guard let index else {
                suites.append(["name": head])
                return true
            }
            if isWholeSuite(suites[index]) { return false }
            var node = suites[index]
            node.removeValue(forKey: "suites")
            node.removeValue(forKey: "testFunctions")
            suites[index] = node
            return true
        }

        let function = leafFunction(in: rest)

        guard let index else {
            var node: [String: Any] = ["name": head]

            if let function {
                node["testFunctions"] = [function]
            } else {
                var children: [[String: Any]] = []
                _ = addToSuites(rest, in: &children)
                node["suites"] = children
            }
            suites.append(node)
            return true
        }

        var node = suites[index]
        // The whole suite is already skipped, so a narrower entry adds nothing.
        if isWholeSuite(node) { return false }

        if let function {
            var functions: [String] = array(forKey: "testFunctions", in: node)
            guard !functions.contains(where: { functionName($0, matches: function) }) else {
                return false
            }
            functions.append(function)
            node["testFunctions"] = functions
        } else {
            var children: [[String: Any]] = array(forKey: "suites", in: node)
            guard addToSuites(rest, in: &children) else { return false }
            node["suites"] = children
        }

        suites[index] = node
        return true
    }

    /// Adds one path to an XCTest class array. Returns `false` when it is already covered.
    private static func addToClasses(_ path: [String], in classes: inout [[String: Any]]) -> Bool {
        guard path.count <= 2,
              let head = path.first,
              let index = classes.firstIndex(where: { $0["name"] as? String == head })
        else { return false }

        var node = classes[index]
        var methods: [String] = array(forKey: "xctestMethods", in: node)
        // An empty method list means the whole class is already skipped.
        guard !methods.isEmpty else { return false }

        if path.count == 1 {
            node.removeValue(forKey: "xctestMethods")
            classes[index] = node
            return true
        }

        guard !methods.contains(where: { functionName($0, matches: path[1]) }) else { return false }
        methods.append(path[1])
        node["xctestMethods"] = methods
        classes[index] = node
        return true
    }

    // MARK: - Dictionary helpers

    /// Reads an array under a key, or an empty array when the key holds nothing of that type.
    private static func array<Element>(forKey key: String, in dict: [String: Any]) -> [Element] {
        dict[key] as? [Element] ?? []
    }

    /// Stores an array under a key, or removes the key when the array is empty.
    ///
    /// Xcode omits an empty array, so writing one would add noise to the file.
    private static func setOrRemove(
        _ list: [some Any],
        forKey key: String,
        in dict: inout [String: Any],
    ) { if list.isEmpty { dict.removeValue(forKey: key) } else { dict[key] = list } }

    // MARK: - Identifier helpers

    /// Splits an identifier such as `"Parent/Child/testDecode()"` into its segments.
    ///
    /// A parameterized Swift Testing name holds parentheses and colons but never a slash, so a
    /// slash always separates two segments.
    private static func segments(of identifier: String) -> [String] {
        identifier.split(separator: "/").map(String.init)
    }

    /// Reports whether a stored function name matches a caller's segment.
    ///
    /// A caller may write `"testDecode"` for a name stored as `"testDecode()"`.
    private static func functionName(_ stored: String, matches segment: String) -> Bool {
        stored == segment || stored == segment + "()"
    }

    /// Reports whether a segment names a test function rather than a nested suite.
    private static func isFunctionName(_ segment: String) -> Bool { segment.hasSuffix("()") }

    /// Returns the last segment of a path when that segment names a test function.
    ///
    /// A path of two or more segments below the current node names a nested suite instead.
    private static func leafFunction(in path: ArraySlice<String>) -> String? {
        guard path.count == 1, let leaf = path.first, isFunctionName(leaf) else { return nil }
        return leaf
    }

    /// Reports whether a suite node skips its whole suite.
    ///
    /// A node with only a `name` names no child, so Xcode skips everything under it.
    private static func isWholeSuite(_ node: [String: Any]) -> Bool {
        let children: [[String: Any]] = array(forKey: "suites", in: node)
        let functions: [String] = array(forKey: "testFunctions", in: node)
        return children.isEmpty && functions.isEmpty
    }
}
