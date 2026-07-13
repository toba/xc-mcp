import MCP
import Foundation
import Subprocess

/// Holds all session defaults as a single value type.
///
/// Used for efficient batch retrieval of session state, reducing actor hops.
public struct SessionDefaults: Sendable, Codable {
    /// Path to the current Xcode project (.xcodeproj)
    public let projectPath: String?
    /// Path to the current Xcode workspace (.xcworkspace)
    public let workspacePath: String?
    /// Path to the current Swift package directory
    public let packagePath: String?
    /// Current scheme name
    public let scheme: String?
    /// Current simulator UDID
    public let simulatorUDID: String?
    /// Current physical device UDID
    public let deviceUDID: String?
    /// Current build configuration (Debug/Release)
    public let configuration: String?
    /// Custom environment variables applied to all build/test/run commands
    public let env: [String: String]?
    /// Extra passthrough arguments appended to every xcodebuild invocation.
    ///
    /// Decoded leniently: session files written before this field existed simply yield `nil`.
    public let extraArgs: [String]?

    /// Memberwise initializer. `extraArgs` defaults to `nil` so existing call sites that predate the
    /// field continue to compile.
    public init(
        projectPath: String?,
        workspacePath: String?,
        packagePath: String?,
        scheme: String?,
        simulatorUDID: String?,
        deviceUDID: String?,
        configuration: String?,
        env: [String: String]?,
        extraArgs: [String]? = nil,
    ) {
        self.projectPath = projectPath
        self.workspacePath = workspacePath
        self.packagePath = packagePath
        self.scheme = scheme
        self.simulatorUDID = simulatorUDID
        self.deviceUDID = deviceUDID
        self.configuration = configuration
        self.env = env
        self.extraArgs = extraArgs
    }
}

/// State of an in-process SwiftPM warmup task for a package.
public enum WarmupState: Sendable, Equatable {
    case running(startedAt: ContinuousClock.Instant)
    case completed(duration: Duration)
    case failed(message: String)
    case cancelled
}

/// Manages session state for the MCP server, including default project, scheme, and device settings
public actor SessionManager {
    /// Closure that performs the actual warmup build for a package path. Injected so tests can
    /// substitute a fake without spawning `swift build` .
    public typealias WarmupRunner = @Sendable (String) async throws -> Void
    /// Path to the current Xcode project (.xcodeproj)
    public private(set) var projectPath: String?

    /// Path to the current Xcode workspace (.xcworkspace)
    public private(set) var workspacePath: String?

    /// Path to the current Swift package directory
    public private(set) var packagePath: String?

    /// Current scheme name
    public private(set) var scheme: String?

    /// Current simulator UDID
    public private(set) var simulatorUDID: String?

    /// Current physical device UDID
    public private(set) var deviceUDID: String?

    /// Current build configuration (Debug/Release)
    public private(set) var configuration: String?

    /// Custom environment variables applied to all build/test/run commands
    public private(set) var env: [String: String]?

    /// Extra passthrough arguments appended to every xcodebuild invocation
    public private(set) var extraArgs: [String]?

    /// Resolves the session file path.
    ///
    /// Priority:
    /// 1. `XC_MCP_SESSION` env var (for wrapper scripts where PPID doesn't group correctly)
    /// 2. PPID-scoped path: `/tmp/xc-mcp-session-{PPID}.json`
    ///
    /// Scoping by PPID ensures focused servers spawned by the same parent (e.g., Claude Code) share
    /// session state, while different agents get isolated files.
    static func resolveFilePath() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["XC_MCP_SESSION"] {
            return URL(fileURLWithPath: envPath)
        }
        let ppid = getppid()
        return .init(fileURLWithPath: "/tmp/xc-mcp-session-\(ppid).json")
    }

    /// The session file path used by this instance.
    let filePath: URL

    /// Modification date of the shared file when we last loaded/saved it. Used to detect external
    /// changes from other server processes.
    private var lastKnownModDate: Date?

    /// In-flight warmup tasks keyed by package path. Used to dedupe and cancel.
    private var warmupTasks: [String: Task<Void, Never>] = [:]

    /// Latest warmup state for each package path (running, completed, failed, cancelled).
    private var warmupStatus: [String: WarmupState] = [:]

    /// Package paths that have already been warmed (or detected warm) this process.
    private var warmedPackages: Set<String> = []

    /// Closure used to perform warmup builds. Default invokes `swift build --build-tests` .
    private let warmupRunner: WarmupRunner

    /// Whether warmup is enabled. Disabled when `XC_MCP_DISABLE_WARMUP` is set, or when explicitly
    /// disabled at init time (e.g. tests).
    private let warmupEnabled: Bool

    /// Default warmup implementation: cold-cache `swift build --build-tests` .
    @Sendable
    private static func defaultWarmupRunner(packagePath: String) async throws {
        let runner = SwiftRunner()
        _ = try await runner.build(
            packagePath: packagePath,
            buildTests: true,
            timeout: SwiftRunner.coldCacheTimeout,
        )
    }

    /// Creates a session manager.
    ///
    /// - Parameters:
    ///   - filePath: Explicit file path for persistence. When `nil` , uses ``resolveFilePath()``
    ///     (PPID-scoped or `XC_MCP_SESSION` env var). Pass an explicit path in tests for isolation.
    ///   - warmupRunner: Override for the SwiftPM warmup builder. When `nil` , uses
    ///     ``defaultWarmupRunner(packagePath:)`` . Tests pass a fake to avoid spawning real
    ///     `swift build` subprocesses.
    ///   - enableWarmup: Force-disable warmup independent of env var. Tests that want to exercise
    ///     the warmup machinery pass `true` with a fake `warmupRunner` ; tests that only test other
    ///     behavior pass `false` .
    public init(
        filePath: URL? = nil,
        warmupRunner: WarmupRunner? = nil,
        enableWarmup: Bool = true,
    ) {
        let resolved = filePath ?? Self.resolveFilePath()
        self.filePath = resolved
        self.warmupRunner = warmupRunner ?? Self.defaultWarmupRunner
        let envDisabled = ProcessInfo.processInfo.environment["XC_MCP_DISABLE_WARMUP"] != nil
        warmupEnabled = enableWarmup && !envDisabled
        let defaults = Self.loadDefaults(from: resolved)
        projectPath = defaults?.projectPath
        workspacePath = defaults?.workspacePath
        packagePath = defaults?.packagePath
        scheme = defaults?.scheme
        simulatorUDID = defaults?.simulatorUDID
        deviceUDID = defaults?.deviceUDID
        configuration = defaults?.configuration
        env = defaults?.env
        extraArgs = defaults?.extraArgs
        lastKnownModDate = Self.modDate(of: resolved)
    }

    /// Loads session defaults from a file path. Static to be callable from nonisolated init.
    private static func loadDefaults(from path: URL) -> SessionDefaults? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }

        do {
            let data = try Data(contentsOf: path)
            return try JSONDecoder().decode(SessionDefaults.self, from: data)
        } catch {
            return nil
        }
    }

    /// Returns the modification date of a file, or nil if it doesn't exist.
    private static func modDate(of path: URL) -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: path.path)[.modificationDate] as? Date
    }

    /// Loads session defaults from the session file, if it exists.
    private nonisolated func loadFromDisk() -> SessionDefaults? {
        Self.loadDefaults(from: filePath)
    }

    /// Returns the modification date of the session file, or nil if it doesn't exist.
    private nonisolated func fileModDate() -> Date? { Self.modDate(of: filePath) }

    /// Reloads session defaults from disk if the shared file has been modified by another server
    /// process since we last loaded or saved.
    private func reloadIfNeeded() {
        let currentModDate = fileModDate()
        guard currentModDate != lastKnownModDate else { return }

        if let defaults = loadFromDisk() {
            projectPath = defaults.projectPath
            workspacePath = defaults.workspacePath
            packagePath = defaults.packagePath
            scheme = defaults.scheme
            simulatorUDID = defaults.simulatorUDID
            deviceUDID = defaults.deviceUDID
            configuration = defaults.configuration
            env = defaults.env
            extraArgs = defaults.extraArgs
        }
        lastKnownModDate = currentModDate
    }

    /// Persists current session defaults to the shared file.
    private func saveToDisk() {
        let defaults = getDefaults()

        do {
            let data = try JSONEncoder().encode(defaults)
            try data.write(to: filePath, options: .atomic)
            lastKnownModDate = fileModDate()
        } catch {
            // Best-effort — don't fail the operation if persistence fails
        }
    }

    /// Deletes the shared session file.
    private func deleteFromDisk() { try? FileManager.default.removeItem(at: filePath) }

    /// Set session defaults
    public func setDefaults(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        packagePath: String? = nil,
        scheme: String? = nil,
        simulatorUDID: String? = nil,
        deviceUDID: String? = nil,
        configuration: String? = nil,
        env: [String: String]? = nil,
        extraArgs: [String]? = nil,
    ) {
        // Resolve to an absolute path eagerly (against the cwd at the time the user supplies it)
        // and persist the absolute form. Storing relative paths lets the DerivedData scoper hash a
        // different cwd-resolved path on each later build, producing a fresh scoped root and a cold
        // rebuild every call (vqc-o14). Absolute paths are idempotent under resolvePath.
        if let projectPath {
            self.projectPath = PathUtility.resolvePath(from: projectPath)
            // Clear workspace if project is set (mutually exclusive)
            if workspacePath == nil { self.workspacePath = nil }
        }
        if let workspacePath {
            self.workspacePath = PathUtility.resolvePath(from: workspacePath)
            // Clear project if workspace is set (mutually exclusive)
            if projectPath == nil { self.projectPath = nil }
        }
        if let packagePath { self.packagePath = PathUtility.resolvePath(from: packagePath) }
        if let scheme { self.scheme = scheme }
        if let simulatorUDID { self.simulatorUDID = simulatorUDID }
        if let deviceUDID { self.deviceUDID = deviceUDID }
        if let configuration { self.configuration = configuration }

        if let env {
            // Deep-merge: new keys add, existing keys update
            var merged = self.env ?? [:]
            merged.merge(env) { _, new in new }
            self.env = merged
        }
        // Replace (not merge): passing extra_args sets the full session list; an empty array clears
        // it. This mirrors the "explicit replaces defaults" resolution semantics.
        if let extraArgs { self.extraArgs = extraArgs.isEmpty ? nil : extraArgs }
        saveToDisk()
        if let active = self.packagePath { triggerWarmupIfNeeded(packagePath: active) }
    }

    /// Clear all session defaults
    public func clear() {
        for (_, task) in warmupTasks { task.cancel() }
        warmupTasks.removeAll()
        warmupStatus.removeAll()
        warmedPackages.removeAll()
        projectPath = nil
        workspacePath = nil
        packagePath = nil
        scheme = nil
        simulatorUDID = nil
        deviceUDID = nil
        configuration = nil
        env = nil
        extraArgs = nil
        deleteFromDisk()
    }

    // MARK: - SwiftPM Warmup

    /// Schedules a background `swift build --build-tests` for `packagePath` so the user's first
    /// `swift_package_test` / `swift_package_build` hits a warm `.build/` cache.
    ///
    /// No-ops when warmup is disabled, the path has already been warmed in this process, a warmup
    /// is already in flight, the cache is already warm, or `Package.swift` doesn't exist at the
    /// path.
    private func triggerWarmupIfNeeded(packagePath: String) {
        guard warmupEnabled else { return }
        guard warmupTasks[packagePath] == nil else { return }
        guard !warmedPackages.contains(packagePath) else { return }
        let pkgFile = URL(fileURLWithPath: packagePath)
            .appendingPathComponent("Package.swift").path
        guard FileManager.default.fileExists(atPath: pkgFile) else { return }
        guard SwiftRunner.isColdCache(packagePath: packagePath) else {
            warmedPackages.insert(packagePath)
            return
        }

        let runner = warmupRunner
        let started = ContinuousClock.now
        warmupStatus[packagePath] = .running(startedAt: started)
        warmupTasks[
            packagePath] = Task.immediateDetached(priority: .background) { [weak self] in
                do {
                    try await runner(packagePath)
                    await self?.completeWarmup(packagePath: packagePath, started: started)
                } catch is CancellationError {
                    await self?.markWarmupCancelled(packagePath: packagePath)
                } catch {
                    await self?.markWarmupFailed(
                        packagePath: packagePath,
                        message: String(describing: error),
                    )
                }
            }
    }

    /// Cancels an in-flight warmup for `packagePath` and waits for the background task to terminate
    /// (which releases the `BuildGuard` flock before the caller invokes its own `swift` command).
    public func cancelWarmupIfRunning(packagePath: String) async {
        guard let task = warmupTasks.removeValue(forKey: packagePath) else { return }
        task.cancel()
        _ = await task.value
    }

    /// Reports the current warmup state for a package, if any.
    public func warmupState(for packagePath: String) -> WarmupState? { warmupStatus[packagePath] }

    private func completeWarmup(packagePath: String, started: ContinuousClock.Instant) {
        warmupTasks[packagePath] = nil
        warmedPackages.insert(packagePath)
        warmupStatus[packagePath] = .completed(duration: ContinuousClock.now - started)
    }

    private func markWarmupCancelled(packagePath: String) {
        warmupTasks[packagePath] = nil
        warmupStatus[packagePath] = .cancelled
    }

    private func markWarmupFailed(packagePath: String, message: String) {
        warmupTasks[packagePath] = nil
        warmupStatus[packagePath] = .failed(message: message)
    }

    private func formatWarmupState(_ state: WarmupState) -> String {
        switch state {
            case let .running(startedAt):
                let elapsed = ContinuousClock.now - startedAt
                return "running (\(formatDuration(elapsed)))"
            case let .completed(duration): return "warmed (built in \(formatDuration(duration)))"
            case let .failed(message): return "failed (\(message.prefix(120)))"
            case .cancelled: return "cancelled"
        }
    }

    private func formatDuration(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m\(secs)s"
    }

    /// Get the effective project or workspace path
    public var effectiveProjectPath: String? {
        reloadIfNeeded()
        return workspacePath ?? projectPath
    }

    /// Check if a project or workspace is configured
    public var hasProject: Bool {
        reloadIfNeeded()
        return projectPath != nil || workspacePath != nil
    }

    /// Get a summary of current session state
    public func summary() -> String {
        reloadIfNeeded()
        var lines: [String] = []

        if let workspacePath {
            lines.append("Workspace: \(workspacePath)")
        } else if let projectPath {
            lines.append("Project: \(projectPath)")
        } else {
            lines.append("Project: (not set)")
        }

        lines.append("Package: \(packagePath ?? "(not set)")")
        if let packagePath, let state = warmupStatus[packagePath] {
            lines.append("  Warmup: \(formatWarmupState(state))")
        }
        lines.append("Scheme: \(scheme ?? "(not set)")")
        lines.append("Configuration: \(configuration ?? "(not set)")")
        lines.append("Simulator: \(simulatorUDID ?? "(not set)")")
        lines.append("Device: \(deviceUDID ?? "(not set)")")

        if let env, !env.isEmpty {
            lines.append("Environment:")
            for key in env.keys.sorted() { lines.append("  \(key)=\(env[key]!)") }
        } else {
            lines.append("Environment: (not set)")
        }

        if let extraArgs, !extraArgs.isEmpty {
            lines.append("Extra args: \(extraArgs.joined(separator: " "))")
        } else {
            lines.append("Extra args: (not set)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Batch Getter

    /// Gets all session defaults in a single actor hop.
    ///
    /// Use this method when you need multiple session values to avoid multiple actor context
    /// switches.
    ///
    /// - Returns: A ``SessionDefaults`` containing all current session values.
    public func getDefaults() -> SessionDefaults {
        reloadIfNeeded()
        return .init(
            projectPath: projectPath,
            workspacePath: workspacePath,
            packagePath: packagePath,
            scheme: scheme,
            simulatorUDID: simulatorUDID,
            deviceUDID: deviceUDID,
            configuration: configuration,
            env: env,
            extraArgs: extraArgs,
        )
    }

    // MARK: - Parameter Resolution

    /// Resolves the simulator UDID from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved simulator UDID.
    /// - Throws: MCPError.invalidParams if no simulator is available.
    public func resolveSimulator(from arguments: [String: Value]) throws(MCPError) -> String {
        reloadIfNeeded()
        if let value = arguments.getString("simulator") { return value }
        if let session = simulatorUDID { return session }
        throw MCPError.invalidParams(
            "simulator is required. Set it with set_session_defaults or pass it directly.",
        )
    }

    /// Resolves the device UDID from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved device UDID.
    /// - Throws: MCPError.invalidParams if no device is available.
    public func resolveDevice(from arguments: [String: Value]) throws(MCPError) -> String {
        reloadIfNeeded()
        if let value = arguments.getString("device") { return value }
        if let session = deviceUDID { return session }
        throw MCPError.invalidParams(
            "device is required. Set it with set_session_defaults or pass it directly.",
        )
    }

    /// Resolves the scheme from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved scheme name.
    /// - Throws: MCPError.invalidParams if no scheme is available.
    public func resolveScheme(from arguments: [String: Value]) throws(MCPError) -> String {
        reloadIfNeeded()
        if let value = arguments.getString("scheme") { return value }
        if let session = scheme { return session }
        throw MCPError.invalidParams(
            "scheme is required. Set it with set_session_defaults or pass it directly.",
        )
    }

    /// Resolves the build configuration from arguments or session defaults.
    ///
    /// Returns `nil` when the caller supplies no `configuration` argument and no session default is
    /// set. A `nil` result means "unspecified" — callers must then omit `-configuration` from the
    /// xcodebuild invocation so xcodebuild honors the scheme's own Build/Run action configuration.
    /// Injecting a "Debug" fallback here overrode the scheme and produced the wrong build settings
    /// (bundle identifier, app path) for schemes whose action uses a non-Debug configuration.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved configuration, or `nil` when unspecified.
    public func resolveConfiguration(
        from arguments: [String: Value],
    ) -> String? {
        reloadIfNeeded()
        return arguments.getString("configuration") ?? configuration
    }

    /// Resolves project and workspace paths from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: A tuple containing the resolved project and workspace paths.
    /// - Throws: MCPError.invalidParams if neither project nor workspace is available.
    public func resolveBuildPaths(
        from arguments: [String: Value]
    ) throws(MCPError) -> (
        project: String?, workspace: String?,
    ) {
        reloadIfNeeded()
        // Resolve to absolute so the path handed to xcodebuild / DerivedDataScoper is stable
        // regardless of the server's cwd (vqc-o14). Idempotent for already-absolute session values;
        // normalizes per-invocation relative overrides and any legacy relative paths persisted
        // before this fix.
        let project = (arguments.getString("project_path") ?? projectPath)
            .map { PathUtility.resolvePath(from: $0) }
        let workspace = (arguments.getString("workspace_path") ?? workspacePath)
            .map { PathUtility.resolvePath(from: $0) }

        if project == nil, workspace == nil {
            // Auto-detect by walking up from cwd; prefer workspace over project
            if let detectedWorkspace = PathUtility.findWorkspacePath() {
                return (nil, detectedWorkspace)
            }
            if let detectedProject = PathUtility.findProjectPath() { return (detectedProject, nil) }
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly.",
            )
        }
        return (project, workspace)
    }

    /// Resolves environment variables by merging session defaults with per-invocation overrides.
    ///
    /// Session env provides the baseline; per-invocation env keys override session values.
    ///
    /// - Parameter arguments: The tool arguments dictionary (may contain an "env" object).
    /// - Returns: An `Environment` value to pass to subprocess runners. Returns `.inherit` when no
    ///   env vars are configured.
    public func resolveEnvironment(from arguments: [String: Value]) -> Environment {
        reloadIfNeeded()
        var merged: [String: String] = env ?? [:]

        // Per-invocation env overrides session defaults
        if case let .object(envDict) = arguments["env"] {
            for (key, value) in envDict { if case let .string(str) = value { merged[key] = str } }
        }

        guard !merged.isEmpty else { return .inherit }

        var overrides: [Environment.Key: String?] = [:]
        for (key, value) in merged { overrides[Environment.Key(stringLiteral: key)] = value }
        return Environment.inherit.updating(overrides)
    }

    /// Resolves extra passthrough xcodebuild arguments from arguments or session defaults.
    ///
    /// Resolution is replace-not-merge: a per-invocation `extra_args` array (even an empty one)
    /// replaces the session default entirely; when the caller omits the key, the session default is
    /// used. This matches the upstream "explicit extraArgs replace defaults" semantics and keeps a
    /// single invocation predictable rather than silently accumulating session + call args.
    ///
    /// - Parameter arguments: The tool arguments dictionary (may contain an `extra_args` array).
    /// - Returns: The extra arguments to append to the xcodebuild invocation (possibly empty).
    public func resolveExtraArgs(from arguments: [String: Value]) -> [String] {
        reloadIfNeeded()
        // Presence of the key — not emptiness — signals an explicit override, so an empty array can
        // suppress the session default for a single call.
        if case .array = arguments["extra_args"] { return arguments.getStringArray("extra_args") }
        return extraArgs ?? []
    }

    /// Resolves the package path from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved package path.
    /// - Throws: MCPError.invalidParams if no package path is available.
    public func resolvePackagePath(from arguments: [String: Value]) throws(MCPError) -> String {
        reloadIfNeeded()
        if let value = arguments.getString("package_path") {
            return PathUtility.resolvePath(from: value)
        }
        if let session = packagePath { return session }
        // Auto-detect by walking up from cwd looking for Package.swift
        if let detected = PathUtility.findPackageRoot() { return detected }
        throw MCPError.invalidParams(
            "package_path is required. Set it with set_session_defaults or pass it directly.",
        )
    }
}
