/// Formats the error and warning lists the build-log tools print.
///
/// `show_build_log` reads its lists from the activity log, and the empty-log fallback reads them
/// from `.dia` files. Both print them the same way, so the caps and the wording live here.
public enum BuildLogDiagnosticList {
    /// The most errors one list prints.
    public static let maxErrors = 50
    /// The most warnings one list prints.
    public static let maxWarnings = 30

    /// Renders the errors, then the warnings, each under a counted heading.
    ///
    /// - Parameters:
    ///   - errors: The errors, each once, in report order.
    ///   - warnings: The warnings, each once, in report order.
    /// - Returns: The lists, or an empty string when both are empty.
    public static func format(errors: [String], warnings: [String]) -> String {
        var text = section(errors, noun: "error", limit: maxErrors)
        let warningText = section(warnings, noun: "warning", limit: maxWarnings)
        if !text.isEmpty, !warningText.isEmpty { text += "\n" }
        return text + warningText
    }

    private static func section(_ items: [String], noun: String, limit: Int) -> String {
        guard !items.isEmpty else { return "" }
        var text = "**\(items.count) \(noun)\(items.count == 1 ? "" : "s"):**\n\n"
        for item in items.prefix(limit) { text += "  \(item)\n" }
        if items.count > limit { text += "  (+\(items.count - limit) more \(noun)s)\n" }
        return text
    }
}
