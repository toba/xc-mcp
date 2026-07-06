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

        if expanded.hasSuffix(".xcodeproj") {
            return [
                expanded + "/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                expanded + "/xcshareddata/swiftpm/Package.resolved",
            ]
        }
        return expanded.hasSuffix(".xcworkspace")
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
        let root: [String: Any]

        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ParseError.malformed("root is not a JSON object")
            }
            root = object
        } catch let error as ParseError {
            throw error
        } catch {
            throw .malformed("invalid JSON: \(error.localizedDescription)")
        }

        // v1: { "version": 1, "object": { "pins": [...] } }
        if let object = root["object"] as? [String: Any],
           let pins = object["pins"] as? [[String: Any]] { return pins.map(Self.pinFromV1) }

        // v2/v3: { "version": 2|3, "pins": [...] }
        if let pins = root["pins"] as? [[String: Any]] { return pins.map(Self.pinFromV2) }

        // A pins file with no dependencies is valid and yields no pins.
        if root["object"] != nil || root["pins"] != nil { return [] }
        throw .malformed("no recognizable pins array (v1 object.pins or v2 pins)")
    }

    private static func pinFromV1(_ pin: [String: Any]) -> ResolvedPin {
        let url = (pin["repositoryURL"] as? String) ?? ""
        let state = pin["state"] as? [String: Any]
        return .init(
            identity: identity(forURL: url),
            location: url,
            version: state?["version"] as? String,
            branch: state?["branch"] as? String,
            revision: state?["revision"] as? String,
        )
    }

    private static func pinFromV2(_ pin: [String: Any]) -> ResolvedPin {
        let location = (pin["location"] as? String) ?? ""
        let identity = (pin["identity"] as? String).map { $0.lowercased() }
            ?? Self.identity(forURL: location)
        let state = pin["state"] as? [String: Any]
        return .init(
            identity: identity,
            location: location,
            version: state?["version"] as? String,
            branch: state?["branch"] as? String,
            revision: state?["revision"] as? String,
        )
    }
}
