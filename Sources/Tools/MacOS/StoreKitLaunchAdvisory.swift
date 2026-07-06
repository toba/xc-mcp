import XCMCPCore
import Foundation

/// Detects when a scheme's Run action references a StoreKit configuration that a direct
/// (non-Xcode-IDE) launch cannot apply, and produces a warning for the macOS launch tools.
///
/// Xcode delivers the scheme's `StoreKitConfigurationFileReference` to the launched process over a
/// private `storekitd` XPC hand-off. The CLI build tools and direct-binary launches
/// (`build_debug_macos`, `build_run_macos`, `launch_mac_app`) don't invoke that path, so
/// `Product.products(for:)` returns an empty array with no error — silently disabling any
/// StoreKit-gated feature. Rather than pretend to apply the config (there is no reliable public
/// mechanism), the launch tools surface this warning so the drop isn't invisible. See okr-ood.
public enum StoreKitLaunchAdvisory {
    /// Returns a warning if the named scheme's Run (LaunchAction) references a StoreKit
    /// configuration, or `nil` when it doesn't (or the scheme can't be found).
    ///
    /// - Parameters:
    ///   - scheme: The scheme being launched. `nil` disables the check (nothing to inspect).
    ///   - projectPath: The `.xcodeproj` container, if known.
    ///   - workspacePath: The `.xcworkspace` container, if known.
    public static func warning(
        scheme: String?,
        projectPath: String?,
        workspacePath: String?,
    ) -> String? {
        guard let scheme, !scheme.isEmpty else { return nil }

        // Shared schemes may live under either the project or the workspace container.
        var schemePath: String?

        for container in [projectPath, workspacePath].compactMap({ $0 }) {
            if let found = SchemePathResolver.findScheme(named: scheme, in: container) {
                schemePath = found
                break
            }
        }
        guard let schemePath else { return nil }

        // Only the Run (LaunchAction) reference matters for a launch — the Test reference applies
        // to `xcodebuild test`, not a direct run.
        let identifiers = SetSchemeStoreKitConfigTool.storeKitIdentifiers(inSchemeAt: schemePath)
        guard let reference = identifiers["LaunchAction"] else { return nil }

        // Note when the reference itself doesn't resolve — that's a second, worse failure mode
        // (nothing would apply even in the IDE).
        let schemeDir = URL(fileURLWithPath: schemePath).deletingLastPathComponent()
        let resolved = schemeDir.appendingPathComponent(reference).standardizedFileURL.path
        let unresolvedNote = FileManager.default.fileExists(atPath: resolved)
            ? ""
            : " (this reference also does not resolve to a file on disk — see validate_scheme)"

        return """
            ⚠︎ StoreKit configuration not applied. Scheme '\(scheme)' Run action references a StoreKit \
            configuration ('\(reference)')\(unresolvedNote), but apps launched directly — not through \
            the Xcode IDE — do not receive it. Xcode injects the config over a private storekitd XPC \
            channel that CLI/direct launches can't replicate, so Product.products(for:) returns an \
            empty array and StoreKit-gated features stay silently disabled. To exercise StoreKit \
            behavior, run the scheme from Xcode (Cmd+R), or drive it from tests via \
            SKTestSession(configurationFileNamed:) — use add_storekit_config to wire the config into a \
            test target.
            """
    }
}
