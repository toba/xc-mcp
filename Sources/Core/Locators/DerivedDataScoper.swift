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
/// resolve another platform's framework slice (e.g. grab `Debug-iphonesimulator/GRDB.framework` for
/// a macOS target), producing confusing
/// `building for 'macOS', but linking in dylib built for 'iOS-simulator'` cascades. The
/// destination's platform is folded into the path as a suffix (`-macosx`, `-iphonesimulator`,
/// `-iphoneos`, …) so the two never collide. When the destination is absent or unrecognized, the
/// base (suffix-free) path is used.
///
/// ## Override behavior
///
/// - Set `XC_MCP_DERIVED_DATA_PATH=<absolute>` to force a specific path (useful in CI).
/// - Set `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1` to fall back to Xcode's default location.
/// - If the caller already added `-derivedDataPath` via `additionalArguments`, scoping is skipped.
public enum DerivedDataScoper {
    /// Xcode's own DerivedData location. Builds land here when scoping is off.
    public static var xcodeDefaultPath: String {
        NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
    }

    /// Returns a one-line note naming the DerivedData root an xcodebuild invocation writes to.
    ///
    /// Build and test results carry this line so a caller never has to guess which tree holds the
    /// build log, the resolved package checkouts, or the compiled products. The scoped root differs
    /// from Xcode's default, and reading the wrong tree costs a full diagnosis cycle.
    ///
    /// - Parameters:
    ///   - workspacePath: Absolute `.xcworkspace` path, if known.
    ///   - projectPath: Absolute `.xcodeproj` path, if known.
    ///   - destination: The xcodebuild `-destination` value the invocation uses.
    ///   - additionalArguments: Args the caller passes to xcodebuild.
    ///   - environment: Process environment (for testing). Defaults to the startup snapshot.
    public static func note(
        workspacePath: String?,
        projectPath: String?,
        destination: String? = nil,
        additionalArguments: [String] = [],
        environment: [String: String] = ProcessEnvironment.current,
    ) -> String {
        if let caller = callerSuppliedPath(in: additionalArguments) {
            return "DerivedData: \(caller) (from -derivedDataPath)"
        }

        if let path = effectivePath(
            workspacePath: workspacePath,
            projectPath: projectPath,
            destination: destination,
            additionalArguments: additionalArguments,
            environment: environment,
        ) { return "DerivedData: \(path)" }

        return "DerivedData: \(xcodeDefaultPath)/<ProjectName>-<hash> (Xcode default, scoping off)"
    }

    /// Returns a DerivedData note for a context that has no build destination yet, such as the
    /// session defaults. The platform suffix reads as a literal placeholder because the platform
    /// only becomes known when a build names its destination.
    public static func sessionNote(
        workspacePath: String?,
        projectPath: String?,
        environment: [String: String] = ProcessEnvironment.current,
    ) -> String {
        if let override = environment["XC_MCP_DERIVED_DATA_PATH"], !override.isEmpty {
            return "\(override) (XC_MCP_DERIVED_DATA_PATH)"
        }

        if scopingIsDisabled(environment: environment) {
            return "\(xcodeDefaultPath)/<ProjectName>-<hash> (Xcode default, scoping off)"
        }

        guard let base = scopedPath(workspacePath: workspacePath, projectPath: projectPath) else {
            return "(no project or workspace set)"
        }
        return "\(base)-<platform>"
    }

    /// Returns the value the caller already passed for `-derivedDataPath`, or `nil` when the flag
    /// is absent or has no value after it.
    static func callerSuppliedPath(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-derivedDataPath"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Reports whether `XC_MCP_DISABLE_DERIVED_DATA_SCOPING` turns scoping off.
    static func scopingIsDisabled(environment: [String: String]) -> Bool {
        guard let disable = environment["XC_MCP_DISABLE_DERIVED_DATA_SCOPING"], !disable.isEmpty
        else { return false }
        let lowered = disable.lowercased()
        return lowered != "0" && lowered != "false"
    }

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
    ///   - environment: Process environment (for testing). Defaults to the startup snapshot.
    public static func effectivePath(
        workspacePath: String?,
        projectPath: String?,
        destination: String? = nil,
        additionalArguments: [String] = [],
        environment: [String: String] = ProcessEnvironment.current,
    ) -> String? {
        if additionalArguments.contains("-derivedDataPath") { return nil }
        if scopingIsDisabled(environment: environment) { return nil }
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
        let hash = ShortHash.hex(of: absolute)
        let base = NSHomeDirectory() + "/Library/Caches/xc-mcp/DerivedData"
        if let slug = platformSlug(forDestination: destination) {
            return "\(base)/\(projectName)-\(hash)-\(slug)"
        }
        return "\(base)/\(projectName)-\(hash)"
    }

    /// Maps an xcodebuild `-destination` string to an SDK-style platform slug used to namespace
    /// DerivedData (mirrors Xcode's `Debug-<sdk>` product-dir naming so the suffix reads
    /// naturally).
    ///
    /// Returns `nil` for a `nil`/empty/unrecognized destination, in which case callers fall back to
    /// the base (suffix-free) path. Simulator variants are checked before the bare OS so
    /// `platform=iOS Simulator` maps to `iphonesimulator`, not `iphoneos`.
    public static func platformSlug(forDestination destination: String?) -> String? {
        guard let destination, !destination.isEmpty else { return nil }
        let lower = destination.lowercased()
        return lower.contains("mac catalyst") || lower.contains("maccatalyst")
            ? "maccatalyst"
            : lower.contains("ios simulator")
                ? "iphonesimulator"
                : lower.contains("tvos simulator")
                    ? "appletvsimulator"
                    : lower.contains("watchos simulator")
                        ? "watchsimulator"
                        : lower.contains("visionos simulator") || lower.contains("xros simulator")
                            ? "xrsimulator"
                            : lower.contains("driverkit")
                                ? "driverkit"
                                : lower.contains("macos")
                                    ? "macosx"
                                    : lower.contains("ios")
                                        ? "iphoneos"
                                        : lower.contains("tvos")
                                            ? "appletvos"
                                            : lower.contains("watchos")
                                                ? "watchos"
                                                : lower.contains("visionos")
                                                    || lower.contains("xros")
                                                    ? "xros"
                                                    : nil
    }
}
