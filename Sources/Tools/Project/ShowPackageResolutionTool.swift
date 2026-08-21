import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Reports, for every remote package in a project, the declared requirement, the pinned version,
/// the newest tag the repository publishes, and why resolution did not take that newest tag.
///
/// A version bump that "does not take" reads the same as a resolver failure: the build keeps
/// compiling the old source. The difference is visible only when the requirement, the pin, and the
/// newest tag sit side by side. This tool puts them on one line each.
public struct ShowPackageResolutionTool: Sendable {
    private let pathUtility: PathUtility
    private let resolvedParser: PackageResolvedParser
    private let gitRunner: GitRunner

    public init(
        pathUtility: PathUtility,
        resolvedParser: PackageResolvedParser = .init(),
        gitRunner: GitRunner = .init(),
    ) {
        self.pathUtility = pathUtility
        self.resolvedParser = resolvedParser
        self.gitRunner = gitRunner
    }

    public func tool() -> Tool {
        .init(
            name: "show_package_resolution",
            description:
                "Report each remote Swift Package's declared requirement, its pinned version from "
                + "Package.resolved, the newest tag the repository publishes, and the reason a "
                + "newer tag was not taken. Answers 'why is my build still on the old version?' in "
                + "one call. Reads the remote tag list over the network unless check_remote is "
                + "false.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "package_url": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Report on this one package only. Omit to report every package.",
                        ),
                    ]),
                    "check_remote": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Query each repository for its newest tag. Defaults to true. Set false "
                                + "to stay offline and report only the requirement and the pin.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path") else {
            throw MCPError.invalidParams("project_path is required")
        }
        let checkRemote = arguments.getBool("check_remote", default: true)
        let wantedURL = arguments.getString("package_url")

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let xcodeproj = try XcodeProj(path: Path(resolvedProjectPath))

            guard let project = try xcodeproj.pbxproj.rootProject() else {
                throw MCPError.internalError("Unable to access project root")
            }

            var packages = project.remotePackages
            if let wantedURL {
                let wanted = PackageResolvedParser.identity(forURL: wantedURL)
                packages = packages.filter {
                    PackageResolvedParser.identity(forURL: $0.repositoryURL ?? "") == wanted
                }
                guard !packages.isEmpty else {
                    throw MCPError.invalidParams(
                        "Swift Package '\(wantedURL)' is not declared in this project.",
                    )
                }
            }

            guard !packages.isEmpty else {
                return CallTool.Result(content: [
                    .text(
                        text: "No remote Swift Packages declared in this project.",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            let pinsFile = resolvedParser.locate(for: resolvedProjectPath)
            let pins = pinsFile.flatMap { try? resolvedParser.parse(fileAt: $0) } ?? []
            let pinsByIdentity = Dictionary(
                pins.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first },
            )

            let reports = await report(
                packages: packages, pins: pinsByIdentity, checkRemote: checkRemote,
            )

            var lines = [
                "Package resolution — \(packages.count) remote package(s)",
                "Pins: " + (pinsFile ?? "(no Package.resolved)"),
                "",
            ]
            lines.append(contentsOf: reports)

            if reports.contains(where: { $0.contains("not upgraded (pinned)") }) {
                lines.append("")
                lines.append(
                    "A package marked 'not upgraded (pinned)' has a newer allowed tag that the pin "
                        + "holds back. Run resolve_packages(update: true, package_url: \"…\") to "
                        + "move that one pin.",
                )
            }

            return CallTool.Result(content: [
                .text(text: lines.joined(separator: "\n"), annotations: nil, _meta: nil),
            ])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to report package resolution: \(error.localizedDescription)",
            )
        }
    }

    // MARK: - Report

    /// Builds one report line per package, sorted by identity.
    ///
    /// The remote tag lists are fetched first, concurrently, because each one costs a network round
    /// trip. Line assembly then runs synchronously over the XcodeProj objects, which are reference
    /// types that must not cross a concurrency boundary.
    private func report(
        packages: [XCRemoteSwiftPackageReference],
        pins: [String: ResolvedPin],
        checkRemote: Bool,
    ) async -> [String] {
        let urls = packages.compactMap(\.repositoryURL)
        let tagsByURL = checkRemote ? await fetchTags(urls: urls) : [:]

        return packages.map { package in
            line(for: package, pins: pins, checkRemote: checkRemote, tagsByURL: tagsByURL)
        }.sorted()
    }

    /// Highest number of `git ls-remote` processes to run at once.
    ///
    /// Each one is a network round trip that holds a subprocess and a 20-second timeout. A project
    /// with thirty packages would otherwise spawn thirty at once and saturate the connection.
    private static let maxConcurrentTagFetches = 6

    /// Reads every repository's version tags concurrently, keyed by URL. A repository that cannot be
    /// reached yields an empty list rather than failing the whole report.
    private func fetchTags(urls: [String]) async -> [String: [SemanticVersion]] {
        let runner = gitRunner
        let unique = Array(Set(urls))

        return await withTaskGroup(of: (String, [SemanticVersion]).self) { group in
            // Prime the group up to the cap, then start one more each time a fetch finishes.
            var next = 0

            while next < min(Self.maxConcurrentTagFetches, unique.count) {
                let url = unique[next]
                group.addTask(name: "show_package_resolution ls-remote \(url)") {
                    (url, (try? await runner.remoteVersionTags(repositoryURL: url)) ?? [])
                }
                next += 1
            }

            var tags: [String: [SemanticVersion]] = [:]
            tags.reserveCapacity(unique.count)

            for await (url, list) in group {
                tags[url] = list

                guard next < unique.count else { continue }
                let pending = unique[next]
                group.addTask(name: "show_package_resolution ls-remote \(pending)") {
                    (pending, (try? await runner.remoteVersionTags(repositoryURL: pending)) ?? [])
                }
                next += 1
            }
            return tags
        }
    }

    /// Renders one package as `identity: requirement …, pinned …, latest …, <reason>`.
    private func line(
        for package: XCRemoteSwiftPackageReference,
        pins: [String: ResolvedPin],
        checkRemote: Bool,
        tagsByURL: [String: [SemanticVersion]],
    ) -> String {
        let url = package.repositoryURL ?? "(no URL)"
        let identity = PackageResolvedParser.identity(forURL: url)
        let requirement = package.versionRequirement
        let requirementText = requirement.map(PackageRequirement.format) ?? "(none)"
        let window = requirement.flatMap(PackageRequirement.versionWindow)
        let pin = pins[identity]

        var parts = ["\(identity): requirement \(requirementText)"]
        if let window { parts[0] += " (\(window))" }
        parts.append("pinned " + (pin?.stateDescription ?? "(none)"))

        guard checkRemote else {
            parts.append(pin == nil ? "not resolved" : "latest not checked (check_remote: false)")
            return parts.joined(separator: ", ")
        }

        guard let newest = tagsByURL[url]?.first else {
            parts.append("latest unknown (no version tags reachable)")
            return parts.joined(separator: ", ")
        }
        parts.append("latest \(newest)")
        parts.append(
            reason(
                pin: pin, requirement: requirement, tags: tagsByURL[url] ?? [], newest: newest,
            ),
        )
        return parts.joined(separator: ", ")
    }

    /// Explains why the newest tag is not the resolved version.
    private func reason(
        pin: ResolvedPin?,
        requirement: XCRemoteSwiftPackageReference.VersionRequirement?,
        tags: [SemanticVersion],
        newest: SemanticVersion,
    ) -> String {
        guard let requirement else { return "no requirement declared" }

        switch requirement {
            case let .branch(branch): return "tracks branch \(branch), tags do not apply"
            case .revision: return "pinned to a raw revision, tags do not apply"
            default: break
        }

        guard let pin, let pinned = pin.version.flatMap(SemanticVersion.init) else {
            return "not resolved — run resolve_packages"
        }

        // The newest tag the requirement actually admits. Prereleases stay out unless the
        // requirement names one, matching SwiftPM's own behavior.
        let allowed = tags.first {
            PackageRequirement.allows($0, requirement: requirement)
                && (!$0.isPrerelease || $0 == pinned)
        }

        // No published tag satisfies the requirement, not even the pinned one. That happens when a
        // tag is deleted or renamed upstream, and it is the fact worth reporting.
        guard let allowed else {
            return "no published tag satisfies the requirement — the remote publishes "
                + "\(tags.count) tag(s) and none falls inside the window, so the pin \(pinned) "
                + "points at a tag that is gone"
        }
        if allowed == pinned {
            return newest > pinned
                ? "up to date within the requirement — \(newest) needs a wider requirement"
                : "up to date"
        }
        return allowed > pinned
            ? "not upgraded (pinned) — \(allowed) is allowed but Package.resolved holds \(pinned)"
            : "pin is ahead of the newest allowed tag \(allowed)"
    }
}
