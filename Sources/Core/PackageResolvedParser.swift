// Package.resolved parsing adapted from crleonard/swift-package-audit (MIT License)
// https://github.com/crleonard/swift-package-audit — reimplemented, not a dependency.
import Foundation

/// A single dependency pin read from a `Package.resolved` file, normalized across the v1 and v2/v3
/// on-disk formats.
public struct ResolvedPin: Sendable, Equatable {
    /// SwiftPM package identity (lowercased basename of the repository URL).
    public let identity: String
    /// Repository URL / location string exactly as recorded in the pins file.
    public let location: String
    /// Resolved semantic version, when the pin is version-based.
    public let version: String?
    /// Resolved branch name, when the pin tracks a branch.
    public let branch: String?
    /// Resolved git revision (commit SHA), when present.
    public let revision: String?

    public init(
        identity: String,
        location: String,
        version: String? = nil,
        branch: String? = nil,
        revision: String? = nil,
    ) {
        self.identity = identity
        self.location = location
        self.version = version
        self.branch = branch
        self.revision = revision
    }
}

/// Reads and normalizes `Package.resolved` pin files.
///
/// Supports both the legacy v1 layout (`object.pins[]` with `package` / `repositoryURL`) and the
/// modern v2/v3 layout (top-level `pins[]` with `identity` / `location`). Purely read-only; never
/// mutates on-disk state.
public struct PackageResolvedParser: Sendable {
    public init() {}

    /// Errors surfaced while locating or decoding a `Package.resolved` file.
    public enum ParseError: Error, Equatable, Sendable {
        case notFound
        case unreadable(String)
        case malformed(String)
    }

    /// Normalizes a repository URL into a SwiftPM package identity: the lowercased final path
    /// component with any trailing `.git` and slash removed.
    public static func identity(forURL url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.hasSuffix(".git") { trimmed.removeLast(4) }
        let base = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init)
            ?? trimmed
        return base.lowercased()
    }

    /// Candidate `Package.resolved` locations for a project, workspace, or SwiftPM package root, in
    /// the order SwiftPM/Xcode would consult them.
    public static func candidateLocations(for path: String) -> [String] {
        let expanded = PathUtility.expandTilde(path)

        return expanded.hasSuffix(".xcodeproj")
            ? [
                expanded + "/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                expanded + "/xcshareddata/swiftpm/Package.resolved",
            ]
            : expanded.hasSuffix(".xcworkspace")
                ? [expanded + "/xcshareddata/swiftpm/Package.resolved"]
                : [expanded + "/Package.resolved"]
    }

    /// Locates the first existing `Package.resolved` for the given project/package path.
    public func locate(for path: String) -> String? {
        Self.candidateLocations(for: path).first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Parses the `Package.resolved` at an explicit file path.
    public func parse(fileAt filePath: String) throws(ParseError) -> [ResolvedPin] {
        let data: Data

        do {
            data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        } catch {
            throw .unreadable(filePath)
        }
        return try decode(data)
    }

    /// Decodes raw `Package.resolved` bytes, auto-detecting the format version.
    public func decode(_ data: Data) throws(ParseError) -> [ResolvedPin] {
        let file: ResolvedFile

        do {
            file = try JSONDecoder().decode(ResolvedFile.self, from: data)
        } catch {
            throw .malformed("invalid Package.resolved: \(error.localizedDescription)")
        }

        // v1: { "version": 1, "object": { "pins": [...] } }
        if let container = file.object { return (container.pins ?? []).map(\.normalizedV1) }

        // v2/v3: { "version": 2|3, "pins": [...] }
        if let pins = file.pins { return pins.map(\.normalizedV2) }

        throw .malformed("no recognizable pins array (v1 object.pins or v2 pins)")
    }

    /// Decodable mirror of a `Package.resolved` file spanning both on-disk layouts: `object.pins`
    /// (v1) and top-level `pins` (v2/v3). Unknown keys (e.g. `version`, `originHash`, `package`,
    /// `kind`) are ignored, and every field is optional so a pins-less container decodes cleanly.
    private struct ResolvedFile: Decodable {
        struct Container: Decodable { let pins: [RawPin]? }

        struct State: Decodable {
            let version: String?
            let branch: String?
            let revision: String?
        }

        struct RawPin: Decodable {
            let identity: String?
            let repositoryURL: String?
            let location: String?
            let state: State?

            /// v1 pin: identity is derived from the `repositoryURL`.
            var normalizedV1: ResolvedPin {
                let url = repositoryURL ?? ""
                return resolved(
                    identity: PackageResolvedParser.identity(forURL: url), location: url)
            }

            /// v2/v3 pin: identity is the recorded (lowercased) value, falling back to deriving it
            /// from the `location`.
            var normalizedV2: ResolvedPin {
                let location = location ?? ""
                let identity = identity.map { $0.lowercased() }
                    ?? PackageResolvedParser.identity(forURL: location)
                return resolved(identity: identity, location: location)
            }

            private func resolved(identity: String, location: String) -> ResolvedPin {
                .init(
                    identity: identity,
                    location: location,
                    version: state?.version,
                    branch: state?.branch,
                    revision: state?.revision,
                )
            }
        }

        let object: Container?
        let pins: [RawPin]?
    }
}
