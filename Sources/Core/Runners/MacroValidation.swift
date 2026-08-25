import Foundation

/// Decides whether an xcodebuild invocation passes `-skipMacroValidation`.
///
/// Xcode stores a per-user approval fingerprint for each macro package. A fresh package resolve
/// invalidates that fingerprint, and the next build stops with
/// `Macro "X" ... must be enabled before it can be used`. Approval happens in the Xcode UI, so a
/// non-interactive build has no way to grant it and the failure repeats on every retry.
///
/// xc-mcp drives builds without a user present, so it passes `-skipMacroValidation` by default. Set
/// `XC_MCP_REQUIRE_MACRO_APPROVAL=1` to restore Xcode's validation.
public enum MacroValidation {
    /// The xcodebuild flag that bypasses macro-approval validation.
    public static let flag = "-skipMacroValidation"

    /// Returns the flag to inject, or an empty array when the caller already passed it or the
    /// environment requires approval.
    ///
    /// - Parameters:
    ///   - additionalArguments: Args the caller plans to pass to xcodebuild.
    ///   - environment: Process environment (for testing). Defaults to the startup snapshot.
    public static func args(
        additionalArguments: [String] = [],
        environment: [String: String] = ProcessEnvironment.current,
    ) -> [String] {
        additionalArguments.contains(flag)
            ? []
            : requiresApproval(environment: environment)
                ? []
                : [flag]
    }

    /// Reports whether `XC_MCP_REQUIRE_MACRO_APPROVAL` turns the default off.
    public static func requiresApproval(
        environment: [String: String] = ProcessEnvironment.current
    ) -> Bool {
        guard let value = environment["XC_MCP_REQUIRE_MACRO_APPROVAL"], !value.isEmpty
        else { return false }
        let lowered = value.lowercased()
        return lowered != "0" && lowered != "false"
    }
}
