import Foundation

/// Detects Xcode's macro-approval failure in build output and names the flag that clears it.
///
/// Xcode records a fingerprint for every macro package the user approves in the IDE. A fresh
/// package resolve changes that fingerprint, so the next build stops with
/// `Macro "X" from package "Y" was changed since a previous approval and must be enabled before it
/// can be used`. No command-line prompt exists to approve it, so a non-interactive build cannot
/// recover on its own. `-skipMacroValidation` is the only way through.
///
/// xc-mcp passes `-skipMacroValidation` by default (see ``MacroValidation``). This advice covers the
/// case where a caller turned that default off.
public enum MacroApprovalAdvice {
    /// Substrings that identify the macro-approval failure across Xcode's phrasings.
    private static let markers = [
        "must be enabled before it can be used",
        "was changed since a previous approval",
    ]

    /// Reports whether the output holds a macro-approval failure.
    ///
    /// Both the subject and the marker must sit on the same line. Xcode uses the identical
    /// `must be enabled before it can be used` wording for a package **plugin**, which needs
    /// `-skipPackagePluginValidation` instead. Testing the two halves against the whole log would
    /// draw macro advice for a plugin failure whenever the word `macro` appears anywhere else in a
    /// long build log.
    public static func isMacroApprovalFailure(_ output: String) -> Bool {
        output.split(separator: "\n").contains { line in
            line.contains("Macro") && markers.contains { line.contains($0) }
        }
    }

    /// Returns guidance for a macro-approval failure, or `nil` when the output holds no such
    /// failure.
    public static func advice(for output: String) -> String? {
        guard isMacroApprovalFailure(output) else { return nil }
        return """
            A macro package needs approval, which no command-line build can grant. Pass \
            `-skipMacroValidation` through `extra_args` to build anyway, or unset \
            `XC_MCP_REQUIRE_MACRO_APPROVAL` to restore the xc-mcp default that already passes it.
            """
    }
}
