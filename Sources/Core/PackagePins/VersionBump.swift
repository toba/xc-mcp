import Foundation

/// How far a pin sweep advances a package's own version when its pins move
public enum VersionBump: String, Sendable, CaseIterable {
    case major, minor, patch

    /// The version that follows `version` under this policy.
    ///
    /// A prerelease identifier and build metadata are dropped, because the result names a release.
    public func next(after version: SemanticVersion) -> SemanticVersion {
        switch self {
            case .major: .init(major: version.major + 1, minor: 0, patch: 0)
            case .minor: .init(major: version.major, minor: version.minor + 1, patch: 0)
            case .patch: .init(major: version.major, minor: version.minor, patch: version.patch + 1)
        }
    }
}
