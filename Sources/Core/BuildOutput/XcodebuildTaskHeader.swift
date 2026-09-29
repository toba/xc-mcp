/// Reads the fields of an xcodebuild task header, such as
/// `Ld /…/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')`.
enum XcodebuildTaskHeader {
    /// Returns the target that `(in target 'X' …)` names in `line`, or `nil` when the line names
    /// none.
    static func target(in line: some StringProtocol) -> String? {
        guard let start = line.range(of: "(in target '") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "'") else { return nil }
        return String(rest[..<end])
    }
}
