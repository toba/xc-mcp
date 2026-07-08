import Foundation

/// Matches a bare 64-char hex target hash. `Regex` is not `Sendable`, so this stays
/// `nonisolated(unsafe)`; it's only ever read, never mutated.
private nonisolated(unsafe) let guidPattern = /[0-9a-f]{64}/

/// Reads Xcode's on-disk PIF (Project Interchange Format) cache.
///
/// Xcode writes the PIF — its internal build-graph representation, used between the IDE and XCBuild
/// — to `<DerivedData>/<Project-hash>/Build/Intermediates.noindex/XCBuildData/PIFCache/` after
/// every build. The cache contains three subdirectories:
///
/// - `workspace/` — workspace-level objects (lists projects)
/// - `project/` — project-level objects (lists targets, includes the .xcodeproj path)
/// - `target/` — target-level objects (top-level `guid` field is the 64-char target ID that appears
///   verbatim in "Multiple targets in the build graph have the target ID …" errors)
///
/// `PIFCacheReader` indexes those files so diagnostic tools can answer:
/// - "what does target X look like in the build graph?" (`dump_pif`)
/// - "which targets share this hash?" (`why_target_id`)
///
/// The reader is purely read-only: it does not invoke `xcodebuild`. If no PIFCache exists yet (e.g.
/// a fresh checkout that's never been built), `load(...)` throws ``Error/cacheMissing``.
public struct PIFCacheReader: Sendable {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        case derivedDataNotFound(projectName: String)
        case cacheMissing(path: String)
        case decode(path: String, underlying: String)

        public var description: String {
            switch self {
                case let .derivedDataNotFound(name):
                    "No DerivedData directory matching '\(name)-*' under "
                        + "~/Library/Developer/Xcode/DerivedData. Build the project at least once."
                case let .cacheMissing(path):
                    "PIFCache not found at \(path). Build the project at least once "
                        + "so Xcode writes its build-graph cache to disk."
                case let .decode(path, underlying):
                    "Failed to decode PIF JSON at \(path): \(underlying)"
            }
        }
    }

    /// A parsed PIF target with the fields tools care about.
    public struct Target: Sendable {
        public let guid: String
        public let name: String
        public let productType: String?
        public let productReferenceName: String?
        public let dependencies: [Dependency]
        public let cacheFileName: String
        public let cacheFilePath: String

        public struct Dependency: Sendable {
            public let guid: String
            public let name: String?
        }
    }

    /// A parsed PIF project with the fields tools care about.
    public struct Project: Sendable {
        public let guid: String
        public let name: String?
        public let path: String?
        /// Target cache-file stems (e.g. `TARGET@v11_hash=abc123...`) listed by the project.
        public let targetRefs: [String]
        public let cacheFileName: String
        public let cacheFilePath: String
    }

    /// A parsed PIF workspace.
    public struct Workspace: Sendable {
        public let guid: String
        public let name: String?
        public let path: String?
        public let projectRefs: [String]
        public let cacheFileName: String
        public let cacheFilePath: String
    }

    /// The loaded PIF cache index.
    public struct Index: Sendable {
        public let cacheRoot: String
        public let derivedDataRoot: String
        public let newestEntryModified: Date?

        public let workspaces: [Workspace]
        public let projects: [Project]
        public let targets: [Target]

        /// All targets, grouped by `guid`. Entries with >1 target are the duplicate build-graph
        /// nodes that produce "Multiple targets in the build graph" errors.
        public let targetsByGuid: [String: [Target]]

        /// Maps a target cache filename (`TARGET@v..._hash=...`) to the projects that list it.
        public let projectsByTargetRef: [String: [Project]]
    }

    public init() {}

    /// Loads the PIF cache for the given project.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the `.xcodeproj`. Used to derive the DerivedData directory name
    ///     (`<basename>-*`) when `derivedDataPath` isn't given.
    ///   - derivedDataPath: Explicit DerivedData project root override (e.g.
    ///     `.../DerivedData/ Thesis-ddfqsiuxmcpnzhcbomdlbbstfbci`). When provided, project-name
    ///     autodetection is skipped.
    ///   - userDerivedDataRoot: The user's `~/Library/Developer/Xcode/DerivedData` (overridable for
    ///     testing). Defaults to the real path.
    public func load(
        projectPath: String,
        derivedDataPath: String? = nil,
        userDerivedDataRoot: String? = nil,
    ) throws(Error) -> Index {
        let derivedDataRoot = try resolveDerivedDataRoot(
            projectPath: projectPath,
            override: derivedDataPath,
            userDerivedDataRoot: userDerivedDataRoot,
        )

        let cacheRoot = URL(fileURLWithPath: derivedDataRoot)
            .appendingPathComponent("Build/Intermediates.noindex/XCBuildData/PIFCache")
            .path

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: cacheRoot, isDirectory: &isDir), isDir.boolValue
        else { throw Error.cacheMissing(path: cacheRoot) }

        let workspaces = try loadWorkspaces(at: cacheRoot)
        let projects = try loadProjects(at: cacheRoot)
        let targets = try loadTargets(at: cacheRoot)

        var targetsByGuid: [String: [Target]] = [:]
        for target in targets { targetsByGuid[target.guid, default: []].append(target) }

        var projectsByTargetRef: [String: [Project]] = [:]

        for project in projects {
            for ref in project.targetRefs { projectsByTargetRef[ref, default: []].append(project) }
        }

        let newest =
            ([
                workspaces.map(\.cacheFilePath),
                projects.map(\.cacheFilePath),
                targets.map(\.cacheFilePath),
            ]
            .flatMap { $0 })
                .compactMap { (path: String) -> Date? in
                    try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date
                }
                .max()

        return .init(
            cacheRoot: cacheRoot,
            derivedDataRoot: derivedDataRoot,
            newestEntryModified: newest,
            workspaces: workspaces,
            projects: projects,
            targets: targets,
            targetsByGuid: targetsByGuid,
            projectsByTargetRef: projectsByTargetRef,
        )
    }

    /// Extracts the target GUID from one of the forms that show up in build errors:
    /// - the raw 64-char hex hash on its own
    /// - the full `target-<Name>-<hash>-SDKROOT:<sdk>:SDK_VARIANT:<sdk>` build-system id
    /// Returns `nil` if no 64-char hex hash is found.
    public static func extractGuid(from raw: String) -> String? {
        if let match = raw.firstMatch(of: guidPattern) { return String(match.output) }
        return nil
    }

    // MARK: - Private

    private func resolveDerivedDataRoot(
        projectPath: String,
        override: String?,
        userDerivedDataRoot: String?,
    ) throws(Error) -> String {
        if let override { return override }

        let userRoot = userDerivedDataRoot
            ?? (NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData")
        let projectName = URL(fileURLWithPath: projectPath)
            .deletingPathExtension()
            .lastPathComponent

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: userRoot) else {
            throw Error.derivedDataNotFound(projectName: projectName)
        }

        let matches: [(name: String, date: Date)] = entries.compactMap { name in
            guard name.hasPrefix(projectName + "-") else { return nil }
            let path = (userRoot as NSString).appendingPathComponent(name)
            guard let date = try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date
            else { return nil }
            return (name, date)
        }

        guard let newest = matches.max(by: { $0.date < $1.date }) else {
            throw Error.derivedDataNotFound(projectName: projectName)
        }

        return (userRoot as NSString).appendingPathComponent(newest.name)
    }

    private func loadWorkspaces(at cacheRoot: String) throws(Error) -> [Workspace] {
        try decodeEach(in: cacheRoot, subdir: "workspace") { (dto: WorkspaceDTO, url) in
            Workspace(
                guid: dto.guid ?? "",
                name: dto.name,
                path: dto.path,
                projectRefs: dto.projects ?? [],
                cacheFileName: url.lastPathComponent,
                cacheFilePath: url.path,
            )
        }
    }

    private func loadProjects(at cacheRoot: String) throws(Error) -> [Project] {
        try decodeEach(in: cacheRoot, subdir: "project") { (dto: ProjectDTO, url) in
            Project(
                guid: dto.guid ?? "",
                name: dto.projectName,
                path: dto.path,
                targetRefs: dto.targets ?? [],
                cacheFileName: url.lastPathComponent,
                cacheFilePath: url.path,
            )
        }
    }

    private func loadTargets(at cacheRoot: String) throws(Error) -> [Target] {
        try decodeEach(in: cacheRoot, subdir: "target") { (dto: TargetDTO, url) in
            Target(
                guid: dto.guid ?? "",
                name: dto.name ?? "<unnamed>",
                productType: dto.productTypeIdentifier,
                productReferenceName: dto.productReference?.name,
                dependencies: (dto.dependencies ?? []).map {
                    Target.Dependency(guid: $0.guid ?? "", name: $0.name)
                },
                cacheFileName: url.lastPathComponent,
                cacheFilePath: url.path,
            )
        }
    }

    /// Decodes every `*-json` file under `<cacheRoot>/<subdir>` into `DTO`, then maps each into a
    /// public model via `transform`. A missing subdirectory yields an empty array; a malformed file
    /// throws ``Error/decode(path:underlying:)``.
    private func decodeEach<DTO: Decodable, Model>(
        in cacheRoot: String,
        subdir: String,
        transform: (DTO, URL) -> Model,
    ) throws(Error) -> [Model] {
        let decoder = JSONDecoder()
        var models: [Model] = []
        let urls = listJSON(in: cacheRoot, subdir: subdir)
        models.reserveCapacity(urls.count)

        for url in urls {
            let dto: DTO

            do {
                dto = try decoder.decode(DTO.self, from: Data(contentsOf: url))
            } catch {
                throw Error.decode(path: url.path, underlying: error.localizedDescription)
            }
            models.append(transform(dto, url))
        }
        return models
    }

    private func listJSON(in cacheRoot: String, subdir: String) -> [URL] {
        let dir = URL(fileURLWithPath: cacheRoot).appendingPathComponent(subdir)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return entries
            .filter { $0.hasSuffix("-json") }
            .map { dir.appendingPathComponent($0) }
    }

    // MARK: - Decodable DTOs

    /// Mirrors the subset of PIF workspace JSON the reader consumes.
    private struct WorkspaceDTO: Decodable {
        let guid: String?
        let name: String?
        let path: String?
        let projects: [String]?
    }

    /// Mirrors the subset of PIF project JSON the reader consumes.
    private struct ProjectDTO: Decodable {
        let guid: String?
        let projectName: String?
        let path: String?
        let targets: [String]?
    }

    /// Mirrors the subset of PIF target JSON the reader consumes.
    private struct TargetDTO: Decodable {
        let guid: String?
        let name: String?
        let productTypeIdentifier: String?
        let productReference: ProductReference?
        let dependencies: [DependencyDTO]?

        struct ProductReference: Decodable { let name: String? }
        struct DependencyDTO: Decodable {
            let guid: String?
            let name: String?
        }
    }

    /// Reads the raw JSON object at a target cache file path. Used by `dump_pif` to surface the
    /// unparsed PIF for inspection.
    public func rawJSON(atPath path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys],
        )
        return String(data: pretty, encoding: .utf8) ?? ""
    }
}
