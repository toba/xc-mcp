import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// One repository a pin sweep may read and write
///
/// A member is either a Swift package, read from its manifests, or an Xcode project, read from the
/// remote package references the project file holds. A repository with a root `Package.swift` is a
/// package. A repository with no root manifest and exactly one `.xcodeproj` is a project.
public struct PinSyncMember: Sendable {
    /// Where a member declares its pins
    public enum Kind: Sendable, Equatable {
        case package

        /// The absolute path to the `.xcodeproj` bundle
        case xcodeProject(path: String)
    }

    /// One `Package.swift` belonging to a member
    public struct Manifest: Sendable {
        /// Absolute path to the manifest
        public let path: String

        /// The path as it reads from the member root, for a report and for staging
        public let relativePath: String

        /// The manifest source at load time
        public let text: String

        public let pins: [ManifestPin]

        /// Local path dependencies the manifest declares, which block the sweep
        public let localPaths: [String]
    }

    /// One remote package reference an Xcode project holds
    public struct ProjectPin: Sendable {
        public let identity: String
        public let url: String

        /// The requirement in the text form `update_swift_package` accepts
        public let requirement: String

        /// The floor the requirement states, absent for a branch or revision requirement
        public let version: SemanticVersion?
    }

    /// Absolute path to the repository root
    public let root: String

    /// The root directory's name, which the report and the `no_tag` list use
    public let name: String

    /// SwiftPM identity of the package this member publishes
    public let identity: String

    public let kind: Kind

    public let manifests: [Manifest]

    public let projectPins: [ProjectPin]

    /// Every identity this member pins, across every manifest and project reference
    public var pinnedIdentities: Set<String> {
        var identities = Set(projectPins.map(\.identity))
        for manifest in manifests { identities.formUnion(manifest.pins.map(\.identity)) }
        return identities
    }

    /// Loads a member from disk.
    ///
    /// The manifests are the root `Package.swift` and every `Package.swift` one directory below the
    /// root. The nested form is how a benchmark suite declares its own dependencies, and it carries
    /// its own `Package.resolved`. The walk stops at one level so it never descends into a build
    /// directory full of checked-out dependencies.
    ///
    /// - Parameter root: Absolute path to the repository root.
    /// - Returns: The loaded member.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the path names no readable member.
    public static func load(root: String) throws(MCPError) -> PinSyncMember {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw .invalidParams("Member '\(root)' is not a directory") }

        let name = URL(fileURLWithPath: root).lastPathComponent
        let entries = (try? fileManager.contentsOfDirectory(atPath: root)) ?? []
        let manifests = try loadManifests(root: root, entries: entries)

        if !manifests.contains(where: { $0.relativePath == "Package.swift" }) {
            let projects = entries.filter { $0.hasSuffix(".xcodeproj") }.sorted()
            guard projects.count == 1 else {
                throw .invalidParams(
                    projects.isEmpty
                        ? "Member '\(name)' holds no root Package.swift and no .xcodeproj"
                        : "Member '\(name)' holds \(projects.count) Xcode projects, so the sweep "
                            + "cannot tell which one declares its pins",
                )
            }
            let projectPath = root + "/" + projects[0]
            return try .init(
                root: root,
                name: name,
                identity: PackageResolvedParser.identity(forURL: name),
                kind: .xcodeProject(path: projectPath),
                manifests: manifests,
                projectPins: loadProjectPins(at: projectPath),
            )
        }

        return .init(
            root: root,
            name: name,
            identity: PackageResolvedParser.identity(forURL: name),
            kind: .package,
            manifests: manifests,
            projectPins: [],
        )
    }

    /// Reads the root manifest and every manifest one directory below it.
    private static func loadManifests(
        root: String,
        entries: [String],
    ) throws(MCPError) -> [Manifest] {
        var relativePaths: [String] = []
        if entries.contains("Package.swift") { relativePaths.append("Package.swift") }

        let fileManager = FileManager.default

        for entry in entries.sorted() where !entry.hasPrefix(".") {
            let nested = root + "/" + entry + "/Package.swift"

            if fileManager.fileExists(atPath: nested) {
                relativePaths.append(entry + "/Package.swift")
            }
        }

        var manifests: [Manifest] = []
        manifests.reserveCapacity(relativePaths.count)

        for relativePath in relativePaths {
            let path = root + "/" + relativePath
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                throw .invalidParams("Cannot read \(path)")
            }
            let reading = ManifestPins.read(text)
            manifests.append(.init(
                path: path, relativePath: relativePath, text: text, pins: reading.pins,
                localPaths: reading.localPaths,
            ))
        }
        return manifests
    }

    /// Reads the remote package references an Xcode project holds.
    private static func loadProjectPins(at projectPath: String) throws(MCPError) -> [ProjectPin] {
        do {
            let xcodeproj = try XcodeProj(path: Path(projectPath))
            guard let project = try xcodeproj.pbxproj.rootProject() else {
                throw MCPError.invalidParams("Cannot read the root object of \(projectPath)")
            }
            return project.remotePackages.compactMap { reference in
                guard let url = reference.repositoryURL else { return nil }
                let requirement = reference.versionRequirement
                return ProjectPin(
                    identity: PackageResolvedParser.identity(forURL: url),
                    url: url,
                    requirement: requirement.map(PackageRequirement.format) ?? "(none)",
                    version: requirement.flatMap(PackageRequirement.minimumVersion),
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw .invalidParams("Cannot read \(projectPath): \(error)")
        }
    }
}
