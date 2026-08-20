import Foundation

/// One diagnostic emitted by the DocC documentation compiler.
public struct DocCDiagnostic: Sendable, Equatable {
    /// Severity as DocC reports it: `error`, `warning`, `note`, or `hint`.
    public let severity: String

    /// One-line description of the problem.
    public let summary: String

    /// Longer description. DocC omits it for most diagnostics.
    public let explanation: String?

    /// Absolute path of the file the diagnostic points at. Nil for a catalog-wide diagnostic.
    public let sourcePath: String?

    /// One-based line the diagnostic starts on.
    public let line: Int?

    /// One-based column the diagnostic starts on.
    public let column: Int?

    /// Summaries of the fix-its DocC offers.
    public let solutions: [String]

    /// Creates a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: Severity as DocC reports it.
    ///   - summary: One-line description of the problem.
    ///   - explanation: Longer description, when DocC emits one.
    ///   - sourcePath: Absolute path of the file the diagnostic points at.
    ///   - line: One-based start line.
    ///   - column: One-based start column.
    ///   - solutions: Summaries of the offered fix-its.
    public init(
        severity: String,
        summary: String,
        explanation: String? = nil,
        sourcePath: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        solutions: [String] = [],
    ) {
        self.severity = severity
        self.summary = summary
        self.explanation = explanation
        self.sourcePath = sourcePath
        self.line = line
        self.column = column
        self.solutions = solutions
    }

    /// True when the diagnostic reports a documentation link DocC could not resolve.
    ///
    /// These are the diagnostics that matter most to an agent checking a catalog. A symbol link in
    /// an article that names a declaration DocC cannot see produces one.
    public var isUnresolvedReference: Bool {
        let phrases = [
            "doesn't exist at",
            "couldn't be resolved",
            "can't resolve",
            "is ambiguous at",
            "has no member",
        ]
        let lowered = summary.lowercased()
        return phrases.contains { lowered.contains($0) }
    }
}

/// Reads the diagnostics DocC writes with `--diagnostics-file`.
public enum DocCDiagnosticParser: Sendable {
    /// Decodes the JSON diagnostics file DocC writes for `--diagnostics-file`.
    ///
    /// - Parameter data: Contents of the diagnostics file.
    /// - Returns: The diagnostics in the order DocC wrote them.
    /// - Throws: A `DecodingError` when the file does not match the DocC diagnostic file format.
    public static func parse(diagnosticsFile data: Data) throws -> [DocCDiagnostic] {
        let file = try JSONDecoder().decode(DiagnosticFile.self, from: data)
        return file.diagnostics.map { entry in
            DocCDiagnostic(
                severity: entry.severity,
                summary: entry.summary,
                explanation: entry.explanation,
                sourcePath: entry.source.map(Self.filePath),
                line: entry.range?.start.line,
                column: entry.range?.start.column,
                solutions: entry.solutions?.map(\.summary) ?? [],
            )
        }
    }

    /// Parses DocC console output.
    ///
    /// Used when the diagnostics file is missing, which happens on a toolchain whose `docc` does
    /// not support `--diagnostics-file`.
    ///
    /// - Parameter output: Combined stdout and stderr of `docc convert`.
    /// - Returns: The diagnostics found in the output.
    public static func parseConsole(_ output: String) -> [DocCDiagnostic] {
        var diagnostics: [DocCDiagnostic] = []

        for line in BuildLogLines.split(output) {
            guard let parsed = parseConsoleLine(line) else { continue }
            diagnostics.append(parsed)
        }
        return diagnostics
    }

    /// Parses one console line of the form `path:line:column: severity: message`.
    private static func parseConsoleLine(_ line: String) -> DocCDiagnostic? {
        let severities = ["error", "warning", "note", "hint"]

        for severity in severities {
            let marker = ": \(severity): "
            guard let markerRange = line.range(of: marker) else { continue }
            let location = String(line[line.startIndex..<markerRange.lowerBound])
            let message = String(line[markerRange.upperBound...])
            let parts = location.split(separator: ":")
            // A location is `path`, `path:line`, or `path:line:column`. The path itself may hold a
            // colon, so read the numbers from the end.
            var column: Int?
            var lineNumber: Int?
            var pathParts = parts

            if let last = pathParts.last, let value = Int(last) {
                column = value
                pathParts.removeLast()
            }
            if let last = pathParts.last, let value = Int(last) {
                lineNumber = value
                pathParts.removeLast()
            }
            // A single number is the line, not the column.
            if lineNumber == nil {
                lineNumber = column
                column = nil
            }
            let path = pathParts.joined(separator: ":")
            return DocCDiagnostic(
                severity: severity,
                summary: message.trimmingCharacters(in: .whitespaces),
                sourcePath: path.isEmpty ? nil : path,
                line: lineNumber,
                column: column,
            )
        }
        return nil
    }

    /// Converts the `file://` URL DocC writes into a plain path.
    private static func filePath(_ source: String) -> String { URL(string: source)?.path ?? source }
}

// MARK: - Diagnostic file format

/// Top level of the JSON file DocC writes for `--diagnostics-file`.
private struct DiagnosticFile: Decodable {
    let diagnostics: [Entry]

    struct Entry: Decodable {
        let severity: String
        let summary: String
        let explanation: String?
        let source: String?
        let range: Range?
        let solutions: [Solution]?
    }

    struct Range: Decodable {
        let start: Position
    }

    struct Position: Decodable {
        let line: Int
        let column: Int
    }

    struct Solution: Decodable {
        let summary: String
    }
}

// MARK: - Formatting

/// Renders DocC diagnostics as markdown for an MCP tool result.
public enum DocCDiagnosticFormatter: Sendable {
    /// Groups diagnostics by source file and renders them as markdown.
    ///
    /// Files that hold an unresolved reference come first, because an unresolved reference is the
    /// failure a catalog check looks for.
    ///
    /// - Parameters:
    ///   - diagnostics: The diagnostics to render.
    ///   - basePath: Directory the reported paths are shown relative to.
    /// - Returns: A markdown section per file, or an empty string when there is nothing to report.
    public static func format(
        _ diagnostics: [DocCDiagnostic],
        relativeTo basePath: String,
    ) -> String {
        guard !diagnostics.isEmpty else { return "" }

        let groups = Dictionary(grouping: diagnostics) { $0.sourcePath ?? "" }
        // The unresolved count is the sort key, so it is computed once per file rather than once
        // per comparison.
        let keyed = groups.map { path, entries in
            (
                path: path, entries: entries,
                unresolved: entries.count(where: \.isUnresolvedReference)
            )
        }
        let ordered = keyed.sorted { lhs, rhs in
            lhs.unresolved != rhs.unresolved
                ? lhs.unresolved > rhs.unresolved
                : lhs.path < rhs.path
        }

        var sections: [String] = []
        sections.reserveCapacity(ordered.count)

        for (path, entries, _) in ordered {
            let title = path.isEmpty
                ? "Catalog"
                : PathUtility.relativePath(path, from: basePath)
            let sorted = entries.sorted { lhs, rhs in
                lhs.line != rhs.line
                    ? (lhs.line ?? 0) < (rhs.line ?? 0)
                    : (lhs.column ?? 0) < (rhs.column ?? 0)
            }
            var lines = ["### \(title)"]

            for entry in sorted {
                lines.append(line(for: entry))
                if let explanation = entry.explanation, !explanation.isEmpty {
                    lines.append("  - \(explanation)")
                }
                for solution in entry.solutions { lines.append("  - fix: \(solution)") }
            }
            sections.append(lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Counts the diagnostics by severity and by unresolved reference.
    ///
    /// - Parameter diagnostics: The diagnostics to count.
    /// - Returns: A one-line summary such as `2 errors, 8 warnings (6 unresolved references)`.
    public static func summary(_ diagnostics: [DocCDiagnostic]) -> String {
        guard !diagnostics.isEmpty else { return "No diagnostics" }

        var parts: [String] = []

        for severity in ["error", "warning", "note", "hint"] {
            let count = diagnostics.count { $0.severity == severity }
            guard count > 0 else { continue }
            parts.append("\(count) \(severity)\(count == 1 ? "" : "s")")
        }
        let unresolved = diagnostics.count(where: \.isUnresolvedReference)
        var text = parts.joined(separator: ", ")
        if unresolved > 0 {
            text += " (\(unresolved) unresolved reference\(unresolved == 1 ? "" : "s"))"
        }
        return text
    }

    /// Renders one diagnostic as a markdown list item.
    private static func line(for entry: DocCDiagnostic) -> String {
        var location = ""

        if let line = entry.line {
            location = "\(line)"
            if let column = entry.column { location += ":\(column)" }
            location += " "
        }
        return "- \(location)\(entry.severity): \(entry.summary)"
    }
}
