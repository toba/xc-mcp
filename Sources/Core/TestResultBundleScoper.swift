import Foundation
import CryptoKit

/// Computes a workspace-scoped `.xcresult` bundle path for `xcodebuild test` invocations.
///
/// When callers don't pass `result_bundle_path`, xc-mcp generates a path under
/// `~/Library/Caches/xc-mcp/TestResults/<ProjectName>-<hash>/<UUID>.xcresult`. The bundle
/// is preserved on disk so callers can open it in Xcode or feed it to coverage and
/// attachment tools (`get_coverage_report`, `get_test_attachments`, …). Bundles older than
/// the retention window are pruned opportunistically when a new path is generated.
///
/// User-supplied paths are never managed by this type — they're returned to the caller
/// untouched and never deleted by xc-mcp.
///
/// ## Override behavior
///
/// - `XC_MCP_TEST_RESULTS_PATH=<absolute>` forces a specific base directory (CI use).
/// - `XC_MCP_DISABLE_TEST_RESULTS_SCOPING=1` reverts to the previous unmanaged
///   `$TMPDIR/xc-mcp-test-<UUID>.xcresult` behavior.
public enum TestResultBundleScoper {
    /// Default retention window for managed bundles (7 days).
    public static let defaultRetention: TimeInterval = 7 * 24 * 60 * 60

    /// Returns a managed bundle path that the caller should pass to `xcodebuild
    /// -resultBundlePath`. Creates parent directories and prunes old bundles as a side
    /// effect.
    public static func managedPath(
        workspacePath: String?,
        projectPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> String {
        if isScopingDisabled(environment: environment) {
            return tmpFallback()
        }
        let dir = scopedDir(
            workspacePath: workspacePath,
            projectPath: projectPath,
            environment: environment,
        ) ?? defaultBase(environment: environment)

        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true,
        )
        pruneOldBundles(in: dir)
        return "\(dir)/\(UUID().uuidString).xcresult"
    }

    /// Workspace-scoped subdirectory. Returns `nil` when neither workspace nor project
    /// path is provided (callers fall back to the unscoped base directory).
    public static func scopedDir(
        workspacePath: String?,
        projectPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> String? {
        guard let source = workspacePath ?? projectPath, !source.isEmpty else {
            return nil
        }
        let absolute = URL(fileURLWithPath: source).standardized.path
        let projectName = URL(fileURLWithPath: absolute).deletingPathExtension().lastPathComponent
        let hash = shortHash(of: absolute)
        return "\(defaultBase(environment: environment))/\(projectName)-\(hash)"
    }

    /// Removes managed bundles in `dir` whose modification time is older than `retention`.
    /// Best-effort; failures are silently ignored. Only entries ending in `.xcresult` are
    /// considered, so unrelated files in a misconfigured base directory aren't touched.
    public static func pruneOldBundles(
        in dir: String,
        retention: TimeInterval = defaultRetention,
        now: Date = .init(),
    ) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        let cutoff = now.addingTimeInterval(-retention)
        for entry in entries where entry.hasSuffix(".xcresult") {
            let path = "\(dir)/\(entry)"
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date,
                  modified < cutoff
            else { continue }
            try? fm.removeItem(atPath: path)
        }
    }

    private static func defaultBase(environment: [String: String]) -> String {
        if let override = environment["XC_MCP_TEST_RESULTS_PATH"], !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/Library/Caches/xc-mcp/TestResults"
    }

    private static func isScopingDisabled(environment: [String: String]) -> Bool {
        guard let value = environment["XC_MCP_DISABLE_TEST_RESULTS_SCOPING"],
              !value.isEmpty
        else { return false }
        let lowered = value.lowercased()
        return lowered != "0" && lowered != "false" && lowered != "no"
    }

    private static func tmpFallback() -> String {
        let tempDir = FileManager.default.temporaryDirectory.path
        return "\(tempDir)/xc-mcp-test-\(UUID().uuidString).xcresult"
    }

    /// 12-character hex prefix of SHA-256(path). Matches `DerivedDataScoper`'s naming
    /// convention so callers see consistent project hashes across both caches.
    private static func shortHash(of value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
