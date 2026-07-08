import Foundation

/// Extracts the verbatim compiler/linker diagnostic regions from raw `xcodebuild` output.
///
/// The structured `BuildOutputParser` distills errors into a compact summary, but a link failure's
/// full value is the raw multi-line block `ld` emits — the `Undefined symbols for architecture …`
/// list of `referenced from` objects, or the `duplicate symbol '…' in:` list of colliding
/// frameworks. That block IS the diagnosis (which objects/frameworks collide), so this returns it
/// unaltered rather than reformatting it.
public enum LinkerDiagnostics {
    /// Returns the verbatim error and linker diagnostic regions from `raw`, joined with an ellipsis
    /// separator between non-adjacent regions. Returns an empty string when none are found.
    ///
    /// - Parameters:
    ///   - raw: The full combined stdout/stderr of a build/test run.
    ///   - maxLines: Cap on the total number of emitted lines. When exceeded, the output is
    ///     truncated with a trailing note.
    public static func extract(from raw: String, maxLines: Int = 500) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return "" }

        var include = Set<Int>()

        for (index, line) in lines.enumerated() where isAnchor(line) {
            include.insert(index)

            // One line of leading context — usually the `Ld …`/`CompileC …` command that names the
            // failing target, or the `"symbol", referenced from:` header above an object list.
            var back = index - 1
            while back >= 0 {
                if lines[back].trimmingCharacters(in: .whitespaces).isEmpty { back -= 1; continue }
                include.insert(back)
                break
            }

            // Trailing continuation — indented lines belong to this diagnostic block (the object /
            // framework file lists that `ld` indents under each header). Stop at the first blank or
            // non-indented line; a following non-indented anchor (e.g. `ld: symbol(s) not found …`)
            // is captured independently by the outer loop and merges via index adjacency.
            var forward = index + 1
            while forward < lines.count {
                let next = lines[forward]
                if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                guard next.hasPrefix(" ") || next.hasPrefix("\t") else { break }
                include.insert(forward)
                forward += 1
            }
        }

        guard !include.isEmpty else { return "" }

        // Emit contiguous runs of included indices as blocks, separated by an ellipsis marker.
        var blocks: [String] = []
        var current: [String] = []
        var previous = -2

        for index in include.sorted() {
            if index != previous + 1, !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current = []
            }
            current.append(lines[index])
            previous = index
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }

        var result = blocks.joined(separator: "\n  …\n")
        let resultLines = result.split(separator: "\n", omittingEmptySubsequences: false)

        if resultLines.count > maxLines {
            let kept = resultLines.prefix(maxLines).joined(separator: "\n")
            result = kept
                + "\n  … (\(resultLines.count - maxLines) more diagnostic lines truncated — "
                + "use full: true or read the raw log file)"
        }
        return result
    }

    /// Whether a line begins a compiler/linker diagnostic worth capturing verbatim.
    private static func isAnchor(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        if trimmed.contains("error:") { return true }
        if trimmed.hasPrefix("ld:") { return true }
        if trimmed.hasPrefix("clang:"), trimmed.contains("error") { return true }
        if trimmed.hasPrefix("Undefined symbol") { return true }
        if trimmed.hasPrefix("duplicate symbol") { return true }
        if trimmed.contains("framework not found") || trimmed.contains("library not found") {
            return true
        }
        // `"_symbol", referenced from:` header that opens an undefined-symbol object list.
        if trimmed.hasPrefix("\""), trimmed.contains(", referenced from:") { return true }
        return false
    }
}
