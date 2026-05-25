import Foundation

/// Static analysis of LLDB breakpoint commands to catch pathological conditions before they wedge
/// the session.
///
/// A breakpoint on a **high-frequency symbol** (e.g. `sqlite3_prepare_v2`, `malloc`,
/// `objc_msgSend`) is hit thousands of times per second. If it also carries a **condition that
/// calls inferior functions** (`strncmp`, `strstr`, …), LLDB runs the expression evaluator — which
/// itself executes code in the target — on every single hit. That slows the target by orders of
/// magnitude and, combined with the output flood, can leave the whole debug session unresponsive
/// (the >1h13m wedge in dq5-oel).
///
/// This advisor produces human-readable warnings; it never blocks a command. The caller prepends
/// the warnings to the tool result so the user can switch to a register/memory-only condition or a
/// lighter capture strategy.
public enum BreakpointConditionAdvisor {
    /// Symbols that are invoked extremely often in a typical app. Breaking on any of these — even
    /// without a condition — risks an output flood; with an inferior-calling condition it is almost
    /// guaranteed to wedge.
    static let highFrequencySymbols: Set<String> = [
        "sqlite3_prepare_v2", "sqlite3_prepare_v3", "sqlite3_prepare",
        "sqlite3_step", "sqlite3_bind_text", "sqlite3_column_text",
        "malloc", "calloc", "realloc", "free", "malloc_zone_malloc",
        "objc_msgSend", "objc_msgSendSuper", "objc_msgSendSuper2",
        "objc_retain", "objc_release", "objc_autorelease",
        "memcpy", "memmove", "memset", "strlen", "strcmp", "strncmp",
        "_platform_memmove", "swift_retain", "swift_release",
        "CFRetain", "CFRelease",
    ]

    /// C library functions whose appearance in a *condition* means the condition calls into the
    /// inferior on every breakpoint hit.
    static let inferiorCallFunctions: Set<String> = [
        "strncmp", "strcmp", "strstr", "strlen", "strcasecmp", "strncasecmp",
        "memcmp", "memchr", "strchr", "strrchr",
        "printf", "sprintf", "snprintf", "atoi", "atol", "strtol",
        "NSLog", "objc_msgSend",
    ]

    /// Returns advisory warnings for an LLDB command string. Empty when nothing looks risky.
    ///
    /// Only inspects breakpoint-defining commands (`breakpoint set`, `b`, `breakpoint modify`,
    /// `tbreak`); everything else returns no warnings.
    public static func warnings(for command: String) -> [String] {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        let isBreakpointCommand =
            lower.hasPrefix("breakpoint set") || lower.hasPrefix("breakpoint modify")
            || lower.hasPrefix("br s ") || lower.hasPrefix("br set")
            || lower.hasPrefix("tbreak") || lower == "b" || lower.hasPrefix("b ")
        guard isBreakpointCommand else { return [] }

        var warnings: [String] = []

        if let symbol = matchedHighFrequencySymbol(in: trimmed) {
            warnings.append(
                "⚠️ Breakpoint targets '\(symbol)', a high-frequency symbol that is hit thousands of times per second. Breaking on it can flood output and stall the target. Prefer a breakpoint on your own (less frequently called) frame, or use the SQLite trace / one-shot capture approaches instead.",
            )
        }

        if let condition = extractCondition(from: trimmed),
           let fn = inferiorCallInCondition(condition) {
            warnings.append(
                "⚠️ The breakpoint condition calls '\(fn)(…)', which runs the expression evaluator in the target on every hit — orders-of-magnitude slowdown on a hot symbol, and a known cause of indefinitely wedged sessions. Prefer a condition that only reads registers/memory (e.g. compare a register value) over one that calls inferior functions.",
            )
        }

        return warnings
    }

    /// Flags whose following token names the symbol(s) a breakpoint targets.
    private static let nameFlags: Set<String> = ["-n", "--name", "-N", "--func-regex", "-r"]

    /// Returns the first high-frequency symbol named as a breakpoint target, or `nil`.
    ///
    /// Only the symbol-naming positions are inspected (the token after `-n`/`--name`/`-r`, or the
    /// bare operand of `b`/`tbreak`) so a benign symbol with an inferior call in its *condition*
    /// (e.g. `--condition 'strcmp(...)'`) isn't mistaken for a hot target.
    private static func matchedHighFrequencySymbol(in command: String) -> String? {
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var candidates: [String] = []

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if let eq = token.firstIndex(of: "="), nameFlags.contains(String(token[..<eq])) {
                candidates.append(String(token[token.index(after: eq)...]))
            } else if nameFlags.contains(token), index + 1 < tokens.count {
                candidates.append(tokens[index + 1])
                index += 1
            } else if (token == "b" || token == "tbreak"), index + 1 < tokens.count,
                      !tokens[index + 1].hasPrefix("-") {
                candidates.append(tokens[index + 1])
                index += 1
            }
            index += 1
        }

        for candidate in candidates {
            let cleaned = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            // Exact match, or the symbol appears inside a regex name pattern.
            if let symbol = highFrequencySymbols.first(
                where: { cleaned == $0 || cleaned.contains($0) },
            ) {
                return symbol
            }
        }
        return nil
    }

    /// Extracts the condition expression following `-c`/`--condition`, handling single/double
    /// quotes. Returns `nil` if the command has no condition.
    static func extractCondition(from command: String) -> String? {
        for flag in ["--condition", "-c"] {
            guard let flagRange = command.range(of: flag) else { continue }
            let after = command[flagRange.upperBound...]
                .drop(while: { $0 == " " || $0 == "=" })
            guard let first = after.first else { continue }

            if first == "'" || first == "\"" {
                let body = after.dropFirst()
                if let end = body.firstIndex(of: first) {
                    return String(body[body.startIndex..<end])
                }
                return String(body)
            }
            // Unquoted: take the rest of the line.
            return String(after)
        }
        return nil
    }

    /// Returns the earliest-occurring inferior-calling function name used in `condition`, or `nil`.
    private static func inferiorCallInCondition(_ condition: String) -> String? {
        var best: (fn: String, index: String.Index)?
        for fn in inferiorCallFunctions {
            // Match `fn(` allowing a cast prefix like `(int)strncmp(`.
            guard let range = condition.range(
                of: "\\b\(NSRegularExpression.escapedPattern(for: fn))\\s*\\(",
                options: .regularExpression,
            ) else { continue }
            if best == nil || range.lowerBound < best!.index {
                best = (fn, range.lowerBound)
            }
        }
        return best?.fn
    }
}
