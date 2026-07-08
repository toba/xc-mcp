import Foundation

/// Headless launch policy.
///
/// When `XC_MCP_HEADLESS_LAUNCH=1` (or `true`, case-insensitive) is set, GUI launches that would
/// otherwise steal window focus on macOS are suppressed:
///
/// - macOS app launches via `/usr/bin/open` use `-g` (background, no foreground steal).
/// - `Simulator.app` launches are skipped entirely (`simctl boot` is enough for `simctl`-driven
///   automation).
///
/// Off by default. Ported from getsentry/XcodeBuildMCP commit `59d5ca3e`
/// (`src/utils/focus-policy.ts`).
public enum FocusPolicy {
    public static let envVar = "XC_MCP_HEADLESS_LAUNCH"

    /// Returns true when the headless-launch env var is set to `1` or `true`.
    public static func isHeadlessLaunchMode(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> Bool {
        guard let value = environment[envVar], !value.isEmpty else { return false }
        return value == "1" || value.lowercased() == "true"
    }

    /// Build argv for `/usr/bin/open` to launch a macOS app bundle. Inserts `-g` when headless mode
    /// is enabled.
    public static func openAppArgs(
        appPath: String,
        launchArgs: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> [String] {
        var args: [String] = []
        if isHeadlessLaunchMode(environment: environment) { args.append("-g") }
        args.append(appPath)

        if !launchArgs.isEmpty {
            args.append("--args")
            args.append(contentsOf: launchArgs)
        }
        return args
    }

    /// Build argv for `/usr/bin/open` to surface `Simulator.app`, or `nil` if the launch should be
    /// skipped (headless mode — `simctl boot` is sufficient).
    public static func openSimulatorAppArgs(
        simulatorID: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> [String]? {
        if isHeadlessLaunchMode(environment: environment) { return nil }
        var args = ["-a", "Simulator"]
        if let simulatorID {
            args.append(contentsOf: ["--args", "-CurrentDeviceUDID", simulatorID])
        }
        return args
    }
}
