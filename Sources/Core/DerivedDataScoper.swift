import CryptoKit
import Foundation

/// Computes a workspace-scoped DerivedData path for `xcodebuild` invocations.
///
/// Without an explicit `-derivedDataPath`, Xcode shares one DerivedData directory per (project
/// name, project path) pair across all callers. When several xc-mcp invocations run against the
/// same clone concurrently — different agents, focused servers vs. the monolithic server, etc. —
/// they race on incremental build artifacts inside that shared directory.
///
/// `DerivedDataScoper` returns a deterministic path under
/// `~/Library/Caches/xc-mcp/DerivedData/<ProjectName>-<hash>[-<platform>]` keyed by the absolute
/// workspace/project path and the build destination's platform. Same path + same platform → same
/// scoped directory (so caches are reused), but different clones — and different platforms — get
/// different scoped directories.
///
/// ## Per-platform namespacing
///
/// macOS (`xc-build`) and iOS-simulator (`xc-simulator`) builds against the same project must not
/// share a `Build/Products` / `Build/Intermediates.noindex` tree: a macOS link step can otherwise
/// resolve another platform's framework slice (e.g. grab `Debug-iphonesimulator/GRDB.framework`
/// for a macOS target), producing confusing `building for 'macOS', but linking in dylib built for
/// 'iOS-simulator'` cascades. The destination's platform is folded into the path as a suffix
/// (`-macosx`, `-iphonesimulator`, `-iphoneos`, …) so the two never collide. When the destination
/// is absent or unrecognized, the base (suffix-free) path is used.
///
/// ## Override behavior
///
/// - Set `XC_MCP_DERIVED_DATA_PATH=<absolute>` to force a specific path (useful in CI).
/// - Set `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1` to fall back to Xcode's default location.
/// - If the caller already added `-derivedDataPath` via `additionalArguments`, scoping is skipped.
public enum DerivedDataScoper {
    /// Returns the `-derivedDataPath` value to inject for an xcodebuild invocation, or `nil` if
    /// scoping should be skipped (env disabled, caller-supplied, no project path).
    ///
    /// - Parameters:
    ///   - workspacePath: Absolute `.xcworkspace` path, if known.
    ///   - projectPath: Absolute `.xcodeproj` path, if known.
    ///   - destination: The xcodebuild `-destination` value (e.g. `platform=macOS` or
    ///     `platform=iOS Simulator,id=…`), used to namespace the path by platform. `nil` yields the
    ///     base path.
    ///   - additionalArguments: Args the caller plans to pass to xcodebuild.
    ///   - environment: Process environment (for testing). Defaults to the live env.
    public static func effectivePath(
        workspacePath: String?,
        projectPath: String?,
        destination: String? = nil,
        additionalArguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> String? {
        if additionalArguments.contains("-derivedDataPath") { return nil }
        if let disable = environment["XC_MCP_DISABLE_DERIVED_DATA_SCOPING"],
           !disable.isEmpty,
           disable.lowercased() != "0",
           disable.lowercased() != "false" { return nil }
        if let override = environment["XC_MCP_DERIVED_DATA_PATH"], !override.isEmpty {
            return override
        }
        return scopedPath(
            workspacePath: workspacePath, projectPath: projectPath, destination: destination,
        )
    }

    /// Computes the scoped path for the given workspace/project, ignoring overrides.
    ///
    /// - Parameters:
    ///   - workspacePath: Absolute `.xcworkspace` path, if known.
    ///   - projectPath: Absolute `.xcodeproj` path, if known.
    ///   - destination: The xcodebuild `-destination` value, used to derive the platform suffix.
    /// - Returns: `<cache>/xc-mcp/DerivedData/<ProjectName>-<hash>[-<platform>]`, or `nil` when
    ///   neither workspace nor project path is provided.
    public static func scopedPath(
        workspacePath: String?,
        projectPath: String?,
        destination: String? = nil,
    ) -> String? {
        guard let source = workspacePath ?? projectPath, !source.isEmpty else { return nil }
        let absolute = URL(fileURLWithPath: source).standardized.path
        let projectName = URL(fileURLWithPath: absolute).deletingPathExtension().lastPathComponent
        let hash = shortHash(of: absolute)
        let base = NSHomeDirectory() + "/Library/Caches/xc-mcp/DerivedData"
        if let slug = platformSlug(forDestination: destination) {
            return "\(base)/\(projectName)-\(hash)-\(slug)"
        }
        return "\(base)/\(projectName)-\(hash)"
    }

    /// Maps an xcodebuild `-destination` string to an SDK-style platform slug used to namespace
    /// DerivedData (mirrors Xcode's `Debug-<sdk>` product-dir naming so the suffix reads naturally).
    ///
    /// Returns `nil` for a `nil`/empty/unrecognized destination, in which case callers fall back to
    /// the base (suffix-free) path. Simulator variants are checked before the bare OS so
    /// `platform=iOS Simulator` maps to `iphonesimulator`, not `iphoneos`.
    public static func platformSlug(forDestination destination: String?) -> String? {
        guard let destination, !destination.isEmpty else { return nil }
        let lower = destination.lowercased()
        if lower.contains("mac catalyst") || lower.contains("maccatalyst") { return "maccatalyst" }
        if lower.contains("ios simulator") { return "iphonesimulator" }
        if lower.contains("tvos simulator") { return "appletvsimulator" }
        if lower.contains("watchos simulator") { return "watchsimulator" }
        if lower.contains("visionos simulator") || lower.contains("xros simulator") {
            return "xrsimulator"
        }
        if lower.contains("driverkit") { return "driverkit" }
        if lower.contains("macos") || lower.contains("os x") { return "macosx" }
        if lower.contains("ios") { return "iphoneos" }
        if lower.contains("tvos") { return "appletvos" }
        if lower.contains("watchos") { return "watchos" }
        if lower.contains("visionos") || lower.contains("xros") { return "xros" }
        return nil
    }

    /// 12-character hex prefix of SHA-256(path). Matches Xcode's DerivedData naming style closely
    /// enough to look familiar without colliding with Xcode's own hashes.
    private static func shortHash(of value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
