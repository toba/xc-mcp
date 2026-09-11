import Foundation

/// The package caches an Xcode resolve reads, and the refresh that makes a new tag visible
///
/// Three copies of a dependency sit between a published tag and a resolved pin, and each one can
/// hold a version older than the tag:
///
/// 1. `checkouts/<name>` is the working copy. A resolve that finds one already satisfying the
///    requirement reuses it and writes no pin for it.
/// 2. `repositories/<name>-<hash>` is the DerivedData mirror. Nothing re-fetches it once it exists,
///    so a tag pushed afterwards stays invisible, and a re-clone lands on the same old version.
/// 3. `~/Library/Caches/org.swift.swiftpm/repositories/<name>-<hash>` is the shared cache a new
///    mirror is seeded from. A stale one keeps a fresh mirror stale.
///
/// ``refresh(identities:git:)`` fetches into 2 and 3 and drops 1, which is the cheap fix.
/// ``clear()`` removes the whole tree, which is the reliable one.
public struct SourcePackagesCache: Sendable {
    /// The `SourcePackages` directory inside the DerivedData tree the resolve writes to
    public let directory: String

    /// The shared mirror cache every DerivedData tree seeds its own mirrors from
    public let sharedRepositories: String

    /// Where SwiftPM keeps the shared mirrors for this user
    public static var defaultSharedRepositories: String {
        NSHomeDirectory() + "/Library/Caches/org.swift.swiftpm/repositories"
    }

    /// The working copies a resolve checks out
    public var checkouts: String { directory + "/checkouts" }

    /// The bare git mirrors a checkout is created from
    public var repositories: String { directory + "/repositories" }

    /// Whether the tree exists on disk yet
    public var exists: Bool { FileManager.default.fileExists(atPath: directory) }

    /// How many mirrors fetch at the same time
    static let concurrentFetchLimit = 8

    /// - Parameters:
    ///   - directory: The `SourcePackages` directory the resolve writes to.
    ///   - sharedRepositories: The shared mirror cache. Defaults to SwiftPM's own.
    public init(
        directory: String,
        sharedRepositories: String = Self.defaultSharedRepositories,
    ) {
        self.directory = directory
        self.sharedRepositories = sharedRepositories
    }

    /// Locates the tree a resolve of this project or workspace uses.
    ///
    /// - Parameters:
    ///   - workspacePath: Absolute `.xcworkspace` path, if known.
    ///   - projectPath: Absolute `.xcodeproj` path, if known.
    ///   - destination: The `-destination` value the resolve passes, which namespaces the tree.
    ///   - environment: Process environment. Defaults to the startup snapshot.
    /// - Returns: The cache, or nil when neither path is known and no tree can be named.
    public static func locate(
        workspacePath: String?,
        projectPath: String?,
        destination: String? = nil,
        environment: [String: String] = ProcessEnvironment.current,
    ) -> SourcePackagesCache? {
        if let root = DerivedDataScoper.effectivePath(
            workspacePath: workspacePath,
            projectPath: projectPath,
            destination: destination,
            environment: environment,
        ) { return .init(directory: root + "/SourcePackages") }

        guard let container = workspacePath ?? projectPath,
              let root = xcodeDefaultRoot(for: container) else { return nil }
        return .init(directory: root + "/SourcePackages")
    }

    /// Finds Xcode's own DerivedData directory for a container.
    ///
    /// Xcode derives the directory suffix with a hash this code cannot reproduce, so the search
    /// reads the path each candidate records in its `info.plist` instead.
    ///
    /// - Parameter container: Path to the `.xcodeproj` or `.xcworkspace`.
    /// - Returns: The matching directory, or nil when no candidate records this container.
    static func xcodeDefaultRoot(for container: String) -> String? {
        let base = DerivedDataScoper.xcodeDefaultPath
        let target = URL(fileURLWithPath: container).standardized.path
        let name = URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else {
            return nil
        }

        for entry in entries where entry.hasPrefix(name + "-") {
            let root = base + "/" + entry
            guard let recorded = workspacePath(inInfoPlistAt: root + "/info.plist") else {
                continue
            }
            // A project opened without a workspace records the .xcodeproj itself, and one opened
            // through its inner workspace records a path below it.
            if recorded == target || recorded.hasPrefix(target + "/") { return root }
        }
        return nil
    }

    /// Reads the `WorkspacePath` key out of a DerivedData `info.plist`.
    private static func workspacePath(inInfoPlistAt path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
            let recorded = (plist as? [String: Any])?["WorkspacePath"] as? String
        else { return nil }
        return URL(fileURLWithPath: recorded).standardized.path
    }

    // MARK: - Refreshing

    /// Refreshes the mirrors for the named packages and drops their working copies.
    ///
    /// Nothing re-fetches a mirror once it exists, so this is what makes a tag published after the
    /// tree was created visible to the next resolve. The working copy goes as well, because a
    /// resolve that reuses one writes no pin for it.
    ///
    /// - Parameters:
    ///   - identities: The package identities to refresh.
    ///   - git: The runner used to fetch.
    /// - Returns: One report line per action taken, empty when the tree holds none of the packages.
    public func refresh(
        identities: some Collection<String>,
        git: GitRunner = .init(),
    ) async -> [String] {
        let mirrors = identities.flatMap { mirrorPaths(for: $0) }
        let copies = identities.flatMap { checkoutPaths(for: $0) }

        // Each fetch talks to its own remote, so they run together. The cap keeps a repository with
        // twenty dependencies from opening forty network connections at once.
        let fetched = await withTaskGroup(of: Bool.self) { group in
            var succeeded = 0

            for (offset, mirror) in mirrors.enumerated() {
                if offset >= Self.concurrentFetchLimit, let done = await group.next(), done {
                    succeeded += 1
                }
                group.addTask(name: "fetch-tags") {
                    (try? await git.fetchTags(repository: mirror))?.succeeded ?? false
                }
            }

            for await done in group where done { succeeded += 1 }
            return succeeded
        }

        var lines: [String] = []

        if fetched > 0 {
            lines.append(
                "Fetched tags into \(fetched) package mirror(s), under \(repositories) and in the "
                    + "shared cache at \(sharedRepositories), so a tag published after the tree "
                    + "was created is visible.",
            )
        }

        var dropped: [String] = []

        for copy in copies where (try? FileManager.default.removeItem(atPath: copy)) != nil {
            dropped.append(URL(fileURLWithPath: copy).lastPathComponent)
        }

        if !dropped.isEmpty {
            lines.append(
                "Dropped the working copy for: " + dropped.sorted().joined(separator: ", "),
            )
        }
        return lines
    }

    /// Removes the whole tree, so the next resolve clones every package again.
    ///
    /// - Returns: True when nothing is left at ``directory``.
    @discardableResult
    public func clear() -> Bool {
        guard exists else { return true }
        try? FileManager.default.removeItem(atPath: directory)
        return !exists
    }

    // MARK: - Paths

    /// The mirror directories that belong to one package, in the DerivedData tree and in the shared
    /// cache.
    func mirrorPaths(for identity: String) -> [String] {
        [repositories, sharedRepositories].flatMap { parent in
            Self.mirrorNames(in: Self.entries(of: parent), identity: identity)
                .map { parent + "/" + $0 }
        }
    }

    /// The working copies that belong to one package.
    func checkoutPaths(for identity: String) -> [String] {
        Self.checkoutNames(in: Self.entries(of: checkouts), identity: identity)
            .map { checkouts + "/" + $0 }
    }

    /// The names a caller can look at, and no error when the directory is missing.
    private static func entries(of directory: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    }

    /// Selects the mirror names that belong to one package identity.
    ///
    /// A mirror is named `<basename>-<hash>`, and the basename keeps whatever case the repository
    /// URL carries. The part after the identity has to read as one hash, meaning one run of letters
    /// and digits. Accepting a dash there would let `toba-data` claim the mirror of
    /// `toba-data-manager`.
    ///
    /// - Parameters:
    ///   - names: The directory names to filter.
    ///   - identity: The package identity, as `Package.resolved` records it.
    static func mirrorNames(in names: [String], identity: String) -> [String] {
        let prefix = identity.lowercased() + "-"

        return names.filter { name in
            let lowered = name.lowercased()
            guard lowered.hasPrefix(prefix) else { return false }
            let hash = lowered.dropFirst(prefix.count)
            return !hash.isEmpty && hash.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }

    /// Selects the working-copy names that belong to one package identity.
    ///
    /// A checkout carries the bare basename, so the match is the identity itself.
    static func checkoutNames(in names: [String], identity: String) -> [String] {
        names.filter { $0.lowercased() == identity.lowercased() }
    }

    /// Names every cache that can hold a copy older than the published tag.
    ///
    /// - Parameter identity: The package the paths belong to.
    /// - Returns: One indented line per cache, each saying what that copy does.
    public func pathNotes(for identity: String) -> [String] {
        [
            "  \(checkouts)/\(identity) (the working copy a resolve reuses)",
            "  \(repositories)/\(identity)-<hash> (the DerivedData mirror, which nothing re-fetches)",
            "  \(sharedRepositories)/\(identity)-<hash> (the shared cache a new mirror is "
                + "seeded from)",
        ]
    }

    /// Names the caches when a resolve failed on a revision no mirror holds.
    ///
    /// A mirror that predates the pinned commit fails the checkout instead of reporting an older
    /// newest tag, so the same three caches explain a failure that reads nothing like the first
    /// one.
    ///
    /// - Parameters:
    ///   - output: The resolve's output.
    ///   - identity: The package to name the paths for, absent when none is known.
    /// - Returns: The advice, or nil when the output names no checkout failure.
    public func revisionAdvice(for output: String, identity: String?) -> String? {
        let markers = ["Couldn't check out revision", "could not find revision"]
        guard markers.contains(where: { output.localizedCaseInsensitiveContains($0) }) else {
            return nil
        }

        var lines = [
            "A mirror that predates the pinned commit cannot check it out. Clear the caches below "
                + "and resolve again, or clear the whole tree at \(directory)."
        ]
        if let identity { lines.append(contentsOf: pathNotes(for: identity)) }
        return lines.joined(separator: "\n")
    }
}
