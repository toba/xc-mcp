import Logging
import Foundation
import Subprocess

/// Inspects code-signing metadata of Mach-O binaries and app bundles and detects the Team-ID
/// mismatches that make dyld's library validation abort an app at launch.
///
/// When a hardened-runtime app is signed with a real Apple Development/Distribution identity, dyld
/// enforces *library validation*: every dynamic library it loads must be signed by the same Team ID
/// (or by Apple), unless the app carries the `com.apple.security.cs.disable-library-validation`
/// entitlement. SPM package-product frameworks are frequently ad-hoc signed (`TeamIdentifier=not
/// set`), so an app re-signed with a dev identity while its frameworks stay ad-hoc aborts in dyld
/// before `main` with a cryptic `__abort_with_payload`. This utility surfaces that class of failure
/// with an actionable message before launch.
public enum CodeSignInspector: Sendable {
    private static let logger = Logger(label: "CodeSignInspector")

    /// Code-signing metadata for a single binary or bundle.
    public struct SigningInfo: Sendable, Equatable {
        /// The path that was inspected.
        public let path: String
        /// The Team ID, or `nil` when the code is ad-hoc signed (`TeamIdentifier=not set`).
        public let teamIdentifier: String?
        /// The leaf signing authority (e.g. `Apple Development: Jane (ABC123)`), if any.
        public let authority: String?

        public init(path: String, teamIdentifier: String?, authority: String?) {
            self.path = path
            self.teamIdentifier = teamIdentifier
            self.authority = authority
        }

        /// Whether the code is ad-hoc signed (no Team ID).
        public var isAdHoc: Bool { teamIdentifier == nil }
    }

    /// The result of comparing an app's Team ID against its bundled frameworks.
    public struct ConsistencyResult: Sendable, Equatable {
        /// Signing info for the app's main executable.
        public let app: SigningInfo
        /// Frameworks whose Team ID differs from the app's (the offenders dyld will reject).
        public let mismatches: [SigningInfo]

        public init(app: SigningInfo, mismatches: [SigningInfo]) {
            self.app = app
            self.mismatches = mismatches
        }

        /// Whether any framework would be rejected by library validation.
        public var hasMismatch: Bool { !mismatches.isEmpty }

        /// A human-readable, actionable warning describing the mismatch, or `nil` when consistent.
        public func warning() -> String? {
            guard hasMismatch else { return nil }

            let appTeam = app.teamIdentifier ?? "ad-hoc"
            var lines = [
                "⚠️  Code-signing Team-ID mismatch — dyld library validation may reject these frameworks at launch:",
                "  App signed: Team \(appTeam)\(app.authority.map { " (\($0))" } ?? "")",
            ]
            for offender in mismatches {
                let team = offender.teamIdentifier ?? "ad-hoc (not set)"
                let name = URL(fileURLWithPath: offender.path).lastPathComponent
                lines.append("  \(name): Team \(team) → rejected by library validation")
            }
            lines.append(
                "  Fix: rebuild with CODE_SIGN_IDENTITY=- so the app and its frameworks are uniformly ad-hoc, "
                    + "or re-sign the frameworks with the app's Team ID.",
            )
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Parsing

    /// Parses the output of `codesign -dvv` (which writes to stderr) into a ``SigningInfo``.
    ///
    /// `TeamIdentifier=not set` and a missing line both map to `nil` (ad-hoc). Exposed for testing
    /// without invoking `codesign`.
    public static func parse(_ output: String, path: String) -> SigningInfo {
        var teamIdentifier: String?
        var authority: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("TeamIdentifier=") {
                let value = String(trimmed.dropFirst("TeamIdentifier=".count))
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, value.lowercased() != "not set" {
                    teamIdentifier = value
                }
            } else if authority == nil, trimmed.hasPrefix("Authority=") {
                // The first Authority line is the leaf certificate.
                authority = String(trimmed.dropFirst("Authority=".count))
            }
        }

        return SigningInfo(path: path, teamIdentifier: teamIdentifier, authority: authority)
    }

    /// Compares an app's signing info against its frameworks' and returns the offenders.
    ///
    /// A framework is an offender only when the app is signed with a real Team ID *and* the
    /// framework's Team ID differs (including ad-hoc frameworks). When the app itself is ad-hoc,
    /// library validation is not enforced, so nothing is flagged. Exposed for testing without files.
    public static func evaluateConsistency(
        app: SigningInfo, frameworks: some Sequence<SigningInfo>,
    ) -> ConsistencyResult {
        // Library validation only bites when the app carries a real Team ID.
        guard let appTeam = app.teamIdentifier else {
            return ConsistencyResult(app: app, mismatches: [])
        }
        let mismatches = frameworks.filter { $0.teamIdentifier != appTeam }
        return ConsistencyResult(app: app, mismatches: mismatches)
    }

    // MARK: - Filesystem

    /// Inspects the code-signing metadata of a binary or bundle on disk.
    public static func inspect(_ path: String) async -> SigningInfo {
        let result = try? await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: ["-dvv", path],
            mergeStderr: true,
        )
        return parse(result?.stdout ?? "", path: path)
    }

    /// Checks Team-ID consistency between an app bundle's main executable and the frameworks in its
    /// `Contents/Frameworks` directory.
    ///
    /// - Returns: A ``ConsistencyResult`` when the app could be inspected, or `nil` if `appPath`
    ///   doesn't look like a bundle. A non-`nil` result with `hasMismatch == false` means consistent.
    public static func checkBundleConsistency(appPath: String) async -> ConsistencyResult? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: appPath) else { return nil }

        let appInfo = await inspect(appPath)

        let frameworksDir = "\(appPath)/Contents/Frameworks"
        guard let entries = try? fm.contentsOfDirectory(atPath: frameworksDir) else {
            return ConsistencyResult(app: appInfo, mismatches: [])
        }

        var frameworkInfos: [SigningInfo] = []
        for entry in entries where entry.hasSuffix(".framework") || entry.hasSuffix(".dylib") {
            frameworkInfos.append(await inspect("\(frameworksDir)/\(entry)"))
        }

        return evaluateConsistency(app: appInfo, frameworks: frameworkInfos)
    }
}
