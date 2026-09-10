import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// The version requirement one file declares for one package
public struct DeclaredRequirement: Sendable, Equatable {
    /// The kind of file a requirement sits in
    public enum Source: Sendable, Equatable {
        /// A remote package reference in the Xcode project, which `update_swift_package` rewrites
        case project

        /// A `.package(url:)` line in a local package's manifest, which no tool here rewrites
        case manifest
    }

    /// Whether a requirement admits a version
    public enum Admission: Sendable, Equatable {
        case admits
        case excludes

        /// The declared form states no version window to compare, such as `branch:` in a manifest
        case unknown
    }

    public let identity: String

    /// The requirement in the text form `update_swift_package` accepts, such as `from: 1.2.0`
    public let requirement: String

    /// Absolute path of the file that declares the requirement
    public let file: String

    public let source: Source

    /// Whether the requirement admits the version the search asked about
    public let admission: Admission

    public init(
        identity: String,
        requirement: String,
        file: String,
        source: Source,
        admission: Admission,
    ) {
        self.identity = identity
        self.requirement = requirement
        self.file = file
        self.source = source
        self.admission = admission
    }
}

/// Finds the file that declares a package's version requirement
///
/// A package an Xcode project names itself carries its requirement in the project file. A package
/// that arrives through a local package carries it in that package's `Package.swift`, which
/// `update_swift_package` and `show_package_resolution` never read. `resolve_packages` needs both,
/// because a requirement that still admits the pinned version is the reason resolution wrote no pin
/// back, and only the file that states the requirement can move that pin.
public enum PackageRequirementLocator {
    /// The requirement declared for one package, searched project first.
    ///
    /// The project's own references come first, because those are the ones a tool here rewrites. A
    /// package the project never names arrives through a local package, so the search then walks
    /// each local package's manifest and every manifest those reach by path.
    ///
    /// - Parameters:
    ///   - identity: SwiftPM identity of the package, lowercased.
    ///   - version: The version to test the requirement against. Pass `nil` for a branch or
    ///     revision pin, which reports ``DeclaredRequirement/Admission/unknown``.
    ///   - container: Path to the `.xcodeproj` or `.xcworkspace` the resolve ran against.
    /// - Returns: The requirement and the file that declares it, or `nil` when no file in reach
    ///   declares the package.
    public static func requirement(
        for identity: String,
        pinned version: String?,
        in container: String,
    ) -> DeclaredRequirement? {
        let wanted = version.flatMap { SemanticVersion($0) }

        for projectPath in projects(in: container) {
            guard let project = try? XcodeProj(path: Path(projectPath)).pbxproj.rootProject() else {
                continue
            }

            if let match = remote(
                identity: identity, version: wanted, in: project, file: projectPath,
            ) { return match }

            let directory = (projectPath as NSString).deletingLastPathComponent
            var visited: Set<String> = []

            for local in project.localPackages {
                if let match = manifest(
                    identity: identity,
                    version: wanted,
                    root: absolute(local.relativePath, from: directory),
                    visited: &visited,
                ) { return match }
            }
        }
        return nil
    }

    // MARK: - Project references

    /// Reads the requirement a project's own remote reference states.
    private static func remote(
        identity: String,
        version: SemanticVersion?,
        in project: PBXProject,
        file: String,
    ) -> DeclaredRequirement? {
        for reference in project.remotePackages {
            guard PackageResolvedParser.identity(forURL: reference.repositoryURL ?? "") == identity,
                  let requirement = reference.versionRequirement else { continue }

            return .init(
                identity: identity,
                requirement: PackageRequirement.format(requirement),
                file: file,
                source: .project,
                admission: admission(of: requirement, for: version),
            )
        }
        return nil
    }

    // MARK: - Manifests

    /// Reads the requirement a package's manifest states, following its path dependencies.
    ///
    /// - Parameters:
    ///   - identity: SwiftPM identity of the package to find.
    ///   - version: The version to test the requirement against.
    ///   - root: Directory of the package whose manifest to read.
    ///   - visited: The manifests already read, which stops a path cycle.
    private static func manifest(
        identity: String,
        version: SemanticVersion?,
        root: String,
        visited: inout Set<String>,
    ) -> DeclaredRequirement? {
        let file = absolute("Package.swift", from: root)

        guard visited.insert(file).inserted,
              let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        let reading = ManifestPins.read(text)

        if let pin = reading.pins.first(where: { $0.identity == identity }) {
            return .init(
                identity: identity,
                requirement: describe(pin.requirement),
                file: file,
                source: .manifest,
                admission: admission(of: pin.requirement, for: version),
            )
        }

        for path in reading.localPaths {
            if let match = manifest(
                identity: identity,
                version: version,
                root: absolute(path, from: root),
                visited: &visited,
            ) { return match }
        }
        return nil
    }

    /// Renders a manifest requirement in the text form a project requirement takes. A form the
    /// scanner reads no version out of is named by its keyword alone.
    private static func describe(_ requirement: ManifestPin.Requirement) -> String {
        switch requirement {
            case let .from(version): "from: \(version)"
            case let .other(keyword): "\(keyword):"
        }
    }

    // MARK: - Admission

    private static func admission(
        of requirement: XCRemoteSwiftPackageReference.VersionRequirement,
        for version: SemanticVersion?,
    ) -> DeclaredRequirement.Admission {
        switch requirement {
            case .branch, .revision: return .unknown
            default: break
        }
        guard let version else { return .unknown }
        return PackageRequirement.allows(version, requirement: requirement) ? .admits : .excludes
    }

    /// A manifest floor states an up-to-next-major window, the same window `from:` states in a
    /// project reference. Every other form the scanner reports carries no version to compare.
    private static func admission(
        of requirement: ManifestPin.Requirement,
        for version: SemanticVersion?,
    ) -> DeclaredRequirement.Admission {
        guard case let .from(floor) = requirement, let version else { return .unknown }
        return PackageRequirement.allows(
            version, requirement: .upToNextMajorVersion(floor.description),
        ) ? .admits : .excludes
    }

    // MARK: - Containers

    /// The Xcode projects a container holds: the project itself, or every project a workspace
    /// references.
    private static func projects(in container: String) -> [String] {
        guard container.hasSuffix(".xcworkspace") else {
            return container.hasSuffix(".xcodeproj") ? [container] : []
        }
        guard let workspace = try? XCWorkspace(path: Path(container)) else { return [] }
        let parent = (container as NSString).deletingLastPathComponent
        return projects(in: workspace.data.children, relativeTo: parent)
    }

    /// Walks a workspace's elements and resolves each project reference to an absolute path.
    ///
    /// A group nests, so the walk carries the directory each level resolves against. An absolute
    /// location ignores that directory, and every other schema resolves against it.
    private static func projects(
        in elements: [XCWorkspaceDataElement],
        relativeTo directory: String,
    ) -> [String] {
        var paths: [String] = []

        for element in elements {
            let location = element.location
            let resolved = location.schema == "absolute"
                ? location.path
                : absolute(location.path, from: directory)

            switch element {
                case .file: if resolved.hasSuffix(".xcodeproj") { paths.append(resolved) }
                case let .group(group), let .fileSystemSynchronizedGroup(group):
                    paths.append(contentsOf: projects(in: group.children, relativeTo: resolved))
            }
        }
        return paths
    }

    /// Resolves a relative path against a directory and removes every `.` and `..` component.
    ///
    /// The arithmetic stays lexical. `standardizingPath` consults the file system and rewrites a
    /// symlinked prefix, which would report a path the caller cannot match against the one it
    /// passed in.
    private static func absolute(_ path: String, from directory: String) -> String {
        let joined = path.hasPrefix("/") ? path : directory + "/" + path
        var components: [Substring] = []

        for component in joined.split(separator: "/") {
            switch component {
                case ".": continue
                case "..": if !components.isEmpty { components.removeLast() }
                default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }
}
