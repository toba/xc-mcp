import Foundation

/// Persists the raw, unparsed combined stdout/stderr of the most recent `xcodebuild` build/test run
/// to a PPID-scoped file, so an agent can recover the complete linker/compiler diagnostic verbatim
/// after the parsed summary truncates or mislabels it.
///
/// This exists because the sanctioned recovery paths are unreliable for link failures: Xcode leaves
/// a 0-byte `.xcactivitylog` for some failed link steps, `show_build_log` can return a stale log
/// from an earlier build, and invoking the raw build CLI is often policy-blocked. The captured
/// process output is the one source guaranteed to contain the full `ld` diagnostic block (the
/// `Undefined symbols …`/`duplicate symbol … in:` file lists). The `show_last_build_raw` tool reads
/// this file.
public enum RawBuildLog {
    /// Metadata describing a captured build/test run.
    public struct Metadata: Codable, Sendable {
        /// The xcodebuild action (`build`, `build-for-testing`, `test`, …).
        public let action: String
        /// The `-destination` value the run used.
        public let destination: String
        /// Whether the run succeeded.
        public let succeeded: Bool
        /// Byte count of the captured output.
        public let byteCount: Int
        /// When the output was captured.
        public let capturedAt: Date

        public init(
            action: String, destination: String, succeeded: Bool, byteCount: Int, capturedAt: Date,
        ) {
            self.action = action
            self.destination = destination
            self.succeeded = succeeded
            self.byteCount = byteCount
            self.capturedAt = capturedAt
        }
    }

    /// A loaded capture: the raw output plus its metadata and on-disk path.
    public struct Capture: Sendable {
        public let rawOutput: String
        public let metadata: Metadata?
        public let path: String
    }

    /// Resolves the capture file path, mirroring `SessionManager`'s PPID scoping so sibling focused
    /// servers spawned by the same parent (e.g. Claude Code) share the same last-build capture.
    ///
    /// Priority: `XC_MCP_LAST_BUILD` env override, else `/tmp/xc-mcp-last-build-{PPID}.log`.
    static func logURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["XC_MCP_LAST_BUILD"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: "/tmp/xc-mcp-last-build-\(getppid()).log")
    }

    /// Persists the raw output and metadata for the most recent build/test.
    ///
    /// Best-effort: failures to write are swallowed so capture never breaks a build.
    public static func store(
        rawOutput: String,
        action: String,
        destination: String,
        succeeded: Bool,
    ) {
        store(
            rawOutput: rawOutput, action: action, destination: destination, succeeded: succeeded,
            to: logURL(),
        )
    }

    /// Loads the most recent capture, or `nil` when none has been recorded this session.
    public static func load() -> Capture? { load(from: logURL()) }

    // MARK: - URL-parameterized variants (testable without touching process env)

    static func store(
        rawOutput: String,
        action: String,
        destination: String,
        succeeded: Bool,
        to url: URL,
    ) {
        // Skip trivial captures (e.g. an empty string from a launch failure) so a real prior build's
        // diagnostics aren't clobbered by a no-op.
        guard !rawOutput.isEmpty else { return }

        do {
            try rawOutput.write(to: url, atomically: true, encoding: .utf8)
            let meta = Metadata(
                action: action, destination: destination, succeeded: succeeded,
                byteCount: rawOutput.utf8.count, capturedAt: Date(),
            )
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: url.appendingPathExtension("json"), options: .atomic)
            }
        } catch {
            // Best-effort — don't fail the build if persistence fails.
        }
    }

    static func load(from url: URL) -> Capture? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let meta = (try? Data(contentsOf: url.appendingPathExtension("json")))
            .flatMap { try? JSONDecoder().decode(Metadata.self, from: $0) }
        return Capture(rawOutput: raw, metadata: meta, path: url.path)
    }
}
