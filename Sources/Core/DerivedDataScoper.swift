import Foundation
import CryptoKit

/// Computes a workspace-scoped DerivedData path for `xcodebuild` invocations.
///
/// Without an explicit `-derivedDataPath`, Xcode shares one DerivedData directory per
/// (project name, project path) pair across all callers. When several xc-mcp invocations
/// run against the same clone concurrently — different agents, focused servers vs. the
/// monolithic server, etc. — they race on incremental build artifacts inside that shared
/// directory.
///
/// `DerivedDataScoper` returns a deterministic path under
/// `~/Library/Caches/xc-mcp/DerivedData/<ProjectName>-<hash>` keyed by the absolute
/// workspace/project path. Same path → same scoped directory (so caches are reused), but
/// different clones get different scoped directories.
///
/// ## Override behavior
///
/// - Set `XC_MCP_DERIVED_DATA_PATH=<absolute>` to force a specific path (useful in CI).
/// - Set `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1` to fall back to Xcode's default location.
/// - If the caller already added `-derivedDataPath` via `additionalArguments`, scoping is
///   skipped.
public enum DerivedDataScoper {
    /// Returns the `-derivedDataPath` value to inject for an xcodebuild invocation, or
    /// `nil` if scoping should be skipped (env disabled, caller-supplied, no project path).
    ///
    /// - Parameters:
    ///   - workspacePath: Absolute `.xcworkspace` path, if known.
    ///   - projectPath: Absolute `.xcodeproj` path, if known.
    ///   - additionalArguments: Args the caller plans to pass to xcodebuild.
    ///   - environment: Process environment (for testing). Defaults to the live env.
    public static func effectivePath(
        workspacePath: String?,
        projectPath: String?,
        additionalArguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> String? {
        if additionalArguments.contains("-derivedDataPath") {
            return nil
        }
        if let disable = environment["XC_MCP_DISABLE_DERIVED_DATA_SCOPING"],
           !disable.isEmpty, disable.lowercased() != "0", disable.lowercased() != "false"
        {
            return nil
        }
        if let override = environment["XC_MCP_DERIVED_DATA_PATH"], !override.isEmpty {
            return override
        }
        return scopedPath(workspacePath: workspacePath, projectPath: projectPath)
    }

    /// Computes the scoped path for the given workspace/project, ignoring overrides.
    ///
    /// - Returns: `<cache>/xc-mcp/DerivedData/<ProjectName>-<hash>`, or `nil` when neither
    ///   workspace nor project path is provided.
    public static func scopedPath(
        workspacePath: String?,
        projectPath: String?,
    ) -> String? {
        guard let source = workspacePath ?? projectPath, !source.isEmpty else {
            return nil
        }
        let absolute = URL(fileURLWithPath: source).standardized.path
        let projectName = URL(fileURLWithPath: absolute).deletingPathExtension().lastPathComponent
        let hash = shortHash(of: absolute)
        let base = NSHomeDirectory() + "/Library/Caches/xc-mcp/DerivedData"
        return "\(base)/\(projectName)-\(hash)"
    }

    /// 12-character hex prefix of SHA-256(path). Matches Xcode's DerivedData naming style
    /// closely enough to look familiar without colliding with Xcode's own hashes.
    private static func shortHash(of value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
