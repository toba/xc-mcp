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

/// A file the search had to read and could not
public struct UnreadableProject: Sendable, Equatable {
    /// Absolute path of the container or project file
    public let file: String

    /// What the reader reported
    public let reason: String

    public init(file: String, reason: String) {
        self.file = file
        self.reason = reason
    }

    /// Names a file the reader refused, with the error it reported as the reason.
    ///
    /// Every refusal renders its error the same way, so the choice of rendering lives here.
    public init(file: String, error: some Error) {
        self.init(file: file, reason: String(describing: error))
    }
}

/// Everything one search over a container found
public struct RequirementSearch: Sendable, Equatable {
    /// The requirement a file in reach declares, absent when no file in reach declares the package
    public let requirement: DeclaredRequirement?

    /// One entry per file the search had to read and could not
    ///
    /// A file the reader refuses declares nothing the search can see. A caller that reads
    /// ``requirement`` alone cannot tell that case from a project that names no package, and the
    /// two take opposite remedies.
    public let unreadable: [UnreadableProject]

    public init(requirement: DeclaredRequirement?, unreadable: [UnreadableProject] = []) {
        self.requirement = requirement
        self.unreadable = unreadable
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
    /// - Returns: The requirement and the file that declares it, plus every file the search could
    ///   not read.
    public static func search(
        for identity: String,
        pinned version: String?,
        in container: String,
    ) -> RequirementSearch {
        let wanted = version.flatMap { SemanticVersion($0) }
        var unreadable: [UnreadableProject] = []

        let paths: [String]

        switch projects(in: container) {
            case let .projects(found): paths = found
            case let .unreadable(failure): return .init(requirement: nil, unreadable: [failure])
        }

        for projectPath in paths {
            let loaded: XcodeProj

            do {
                loaded = try XcodeProj(path: Path(projectPath))
            } catch {
                unreadable.append(.init(file: projectPath, error: error))
                continue
            }

            switch reading(identity: identity, version: wanted, in: loaded, file: projectPath) {
                case let .found(match): return .init(requirement: match, unreadable: unreadable)
                case .declaresNothing: continue
                case let .unreadable(failure): unreadable.append(failure)
            }
        }
        return .init(requirement: nil, unreadable: unreadable)
    }

    // MARK: - One project

    /// What one project file yields
    private enum ProjectReading {
        case found(DeclaredRequirement)
        case declaresNothing
        case unreadable(UnreadableProject)
    }

    /// Reads one project's own references, then the manifests its local packages reach.
    ///
    /// The loaded project arrives as a parameter so it outlives the whole read. Each package
    /// reference reaches its object through a weak link to the object graph, so both lists read
    /// empty the moment the loaded project goes away.
    ///
    /// - Parameters:
    ///   - identity: SwiftPM identity of the package to find.
    ///   - version: The version to test the requirement against.
    ///   - loaded: The project to read.
    ///   - file: Absolute path of the project, which a project reference reports as its file.
    private static func reading(
        identity: String,
        version: SemanticVersion?,
        in loaded: XcodeProj,
        file: String,
    ) -> ProjectReading {
        let root: PBXProject?

        do {
            root = try loaded.pbxproj.rootProject()
        } catch {
            return .unreadable(.init(file: file, error: error))
        }
        guard let root else {
            return .unreadable(.init(file: file, reason: "it names no root project"))
        }

        if let match = remote(identity: identity, version: version, in: root, file: file) {
            return .found(match)
        }

        let directory = (file as NSString).deletingLastPathComponent
        var visited: Set<String> = []

        for local in root.localPackages {
            if let match = manifest(
                identity: identity,
                version: version,
                root: absolute(local.relativePath, from: directory),
                visited: &visited,
            ) { return .found(match) }
        }
        return .declaresNothing
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
        return PackageRequirement.allows(version, upToNextMajorFrom: floor) ? .admits : .excludes
    }

    // MARK: - Containers

    /// What a container yields: the projects to search, or the reason it yields none
    private enum ContainerReading {
        case projects([String])
        case unreadable(UnreadableProject)
    }

    /// The Xcode projects a container holds: the project itself, or every project a workspace
    /// references.
    private static func projects(in container: String) -> ContainerReading {
        guard container.hasSuffix(".xcworkspace") else {
            guard container.hasSuffix(".xcodeproj") else {
                return .unreadable(.init(
                    file: container, reason: "it names neither a project nor a workspace",
                ))
            }
            return .projects([container])
        }

        do {
            let workspace = try XCWorkspace(path: Path(container))
            let parent = (container as NSString).deletingLastPathComponent
            return .projects(projects(in: workspace.data.children, relativeTo: parent))
        } catch {
            return .unreadable(.init(file: container, error: error))
        }
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
