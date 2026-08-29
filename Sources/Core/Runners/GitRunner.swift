import MCP
import System
import Foundation
import Subprocess

/// The working-tree and branch state of one repository
public struct GitStatus: Sendable, Equatable {
    /// The checked-out branch, or `nil` when HEAD is detached
    public let branch: String?

    /// The upstream branch HEAD tracks, such as `origin/main`
    public let upstream: String?

    /// Commits the upstream branch holds that HEAD does not
    public let behind: Int

    /// Commits HEAD holds that the upstream branch does not
    public let ahead: Int

    /// Paths with a change in the index
    public let staged: [String]

    /// Paths with a change in the working tree that the index does not hold
    public let unstaged: [String]

    /// Paths git does not track and does not ignore
    public let untracked: [String]

    public init(
        branch: String?,
        upstream: String?,
        behind: Int,
        ahead: Int,
        staged: [String],
        unstaged: [String],
        untracked: [String],
    ) {
        self.branch = branch
        self.upstream = upstream
        self.behind = behind
        self.ahead = ahead
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
    }

    /// Whether the index and the working tree hold no change to a tracked file
    public var isClean: Bool { staged.isEmpty && unstaged.isEmpty }
}

/// Runs git.
///
/// `show_package_resolution` reads the newest tag a package repository publishes so it can say why
/// resolution kept an older version. `sync_package_pins` reads the state of a working tree, then
/// commits, tags and pushes the change it made.
public struct GitRunner: Sendable {
    /// Path to the git executable shipped with the command-line tools.
    private static let gitPath = "/usr/bin/git"

    public init() {}

    /// Lists the version tags a remote publishes, newest first.
    ///
    /// Peeled tag entries (`refs/tags/1.2.0^{}`) are folded into the tag they annotate, and a tag
    /// whose name does not parse as a semantic version is dropped.
    ///
    /// - Parameters:
    ///   - repositoryURL: The remote repository URL.
    ///   - timeout: Maximum time to wait for the remote to answer.
    /// - Returns: The parsed version tags, in descending order.
    /// - Throws: An error when git fails to launch.
    public func remoteVersionTags(
        repositoryURL: String,
        timeout: Duration = .seconds(20),
    ) async throws -> [SemanticVersion] {
        let result = try await ProcessResult.run(
            Self.gitPath,
            arguments: ["ls-remote", "--tags", "--refs", repositoryURL],
            mergeStderr: false,
            timeout: timeout,
        )
        guard result.succeeded else { return [] }
        return Self.parseTags(result.stdout)
    }

    /// Lists the version tags a local repository holds, newest first.
    ///
    /// - Parameters:
    ///   - repository: Path to the repository's work-tree root.
    ///   - timeout: Maximum time to wait.
    /// - Returns: The parsed version tags, in descending order. A tag whose name does not parse as
    ///   a semantic version is dropped.
    public func localVersionTags(
        repository: String,
        timeout: Duration = .seconds(20),
    ) async throws -> [SemanticVersion] {
        let result = try await run(["tag", "--list"], in: repository, timeout: timeout)
        guard result.succeeded else { return [] }
        var seen = Set<SemanticVersion>()

        for line in result.stdout.split(separator: "\n") {
            if let version = SemanticVersion(String(line)) { seen.insert(version) }
        }
        return seen.sorted(by: >)
    }

    /// Reports the work-tree root of the repository containing `path`.
    ///
    /// - Returns: The absolute root path, or `nil` when `path` sits in no repository.
    public func workTreeRoot(
        containing path: String,
        timeout: Duration = .seconds(20),
    ) async throws -> String? {
        let result = try await run(["rev-parse", "--show-toplevel"], in: path, timeout: timeout)
        guard result.succeeded else { return nil }
        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : root
    }

    /// Reads the branch, upstream and working-tree state of a repository in one call.
    ///
    /// - Parameters:
    ///   - repository: Path to the repository's work-tree root.
    ///   - timeout: Maximum time to wait.
    /// - Returns: The parsed status.
    /// - Throws: ``GitError/commandFailed(_:)`` when git reports a failure.
    public func status(
        repository: String,
        timeout: Duration = .seconds(20),
    ) async throws -> GitStatus {
        let result = try await run(
            ["status", "--porcelain=v2", "--branch", "--untracked-files=normal"],
            in: repository,
            timeout: timeout,
        )
        guard result.succeeded else { throw GitError.commandFailed(result.output) }
        return Self.parseStatus(result.stdout)
    }

    /// Stages the named paths.
    ///
    /// The paths are named one by one on purpose. Several agents and the user write to one working
    /// tree at a time, so a sweeping `git add` would stage work nobody meant to include.
    ///
    /// - Parameters:
    ///   - paths: Paths to stage, absolute or relative to `repository`.
    ///   - repository: Path to the repository's work-tree root.
    public func add(
        paths: [String],
        repository: String,
        timeout: Duration = .seconds(60),
    ) async throws -> ProcessResult {
        try await run(["add", "--"] + paths, in: repository, timeout: timeout)
    }

    /// Commits the staged changes.
    public func commit(
        message: String,
        repository: String,
        timeout: Duration = .seconds(60),
    ) async throws -> ProcessResult {
        try await run(["commit", "-m", message], in: repository, timeout: timeout)
    }

    /// Creates an annotated tag on HEAD.
    public func tag(
        _ name: String,
        message: String,
        repository: String,
        timeout: Duration = .seconds(60),
    ) async throws -> ProcessResult {
        try await run(["tag", "-a", name, "-m", message], in: repository, timeout: timeout)
    }

    /// Pushes the current branch to its upstream remote.
    public func push(
        repository: String,
        timeout: Duration = .seconds(180),
    ) async throws -> ProcessResult { try await run(["push"], in: repository, timeout: timeout) }

    /// Pushes one tag to a remote.
    public func pushTag(
        _ name: String,
        remote: String,
        repository: String,
        timeout: Duration = .seconds(180),
    ) async throws -> ProcessResult {
        try await run(["push", remote, name], in: repository, timeout: timeout)
    }

    /// Runs git in a repository directory.
    private func run(
        _ arguments: [String],
        in repository: String,
        timeout: Duration,
    ) async throws -> ProcessResult {
        try await ProcessResult.runSubprocess(
            .path(FilePath(Self.gitPath)),
            arguments: Arguments(arguments),
            workingDirectory: FilePath(repository),
            mergeStderr: false,
            timeout: timeout,
        )
    }

    /// Extracts version tags from `git ls-remote --tags` output.
    ///
    /// Each line reads `<sha>\trefs/tags/<name>`. Duplicate names collapse, so a peeled entry does
    /// not double-count.
    static func parseTags(_ output: String) -> [SemanticVersion] {
        var seen = Set<SemanticVersion>()

        for line in output.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            var name = String(line[line.index(after: tab)...])
            guard name.hasPrefix("refs/tags/") else { continue }
            name.removeFirst("refs/tags/".count)
            if name.hasSuffix("^{}") { name.removeLast(3) }
            if let version = SemanticVersion(name) { seen.insert(version) }
        }
        return seen.sorted(by: >)
    }

    /// Parses `git status --porcelain=v2 --branch` output.
    ///
    /// A `#` line carries branch state. A `1` or `2` line carries a tracked path whose two status
    /// letters report the index and the working tree in that order, where `.` means unchanged. A
    /// `u` line is an unmerged path, which counts as changed on both sides. A `?` line is
    /// untracked.
    static func parseStatus(_ output: String) -> GitStatus {
        var branch: String?
        var upstream: String?
        var behind = 0
        var ahead = 0
        var staged: [String] = []
        var unstaged: [String] = []
        var untracked: [String] = []

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: false)
            guard let kind = fields.first else { continue }

            switch kind {
                case "#":
                    guard fields.count >= 3 else { continue }
                    let value = fields[2...].joined(separator: " ")

                    switch fields[1] {
                        case "branch.head": branch = value == "(detached)" ? nil : value
                        case "branch.upstream": upstream = value
                        case "branch.ab":
                            // Reads "+<ahead> -<behind>".
                            ahead = Int(fields[2].dropFirst()) ?? 0
                            behind = fields.count > 3 ? Int(fields[3].dropFirst()) ?? 0 : 0
                        default: continue
                    }
                case "1":
                    // "1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>"
                    guard fields.count >= 9 else { continue }
                    record(fields[1], fields[8...].joined(separator: " "), &staged, &unstaged)
                case "2":
                    // "2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <score> <path>\t<source>"
                    guard fields.count >= 10 else { continue }
                    let tail = fields[9...].joined(separator: " ")
                    record(fields[1], String(tail.split(separator: "\t")[0]), &staged, &unstaged)
                case "u":
                    guard fields.count >= 11 else { continue }
                    let path = String(fields[10...].joined(separator: " "))
                    staged.append(path)
                    unstaged.append(path)
                case "?":
                    guard fields.count >= 2 else { continue }
                    untracked.append(fields[1...].joined(separator: " "))
                default: continue
            }
        }
        return .init(
            branch: branch,
            upstream: upstream,
            behind: behind,
            ahead: ahead,
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
        )
    }

    /// Files one changed path under the side or sides its two status letters mark.
    ///
    /// The first letter reports the index and the second the working tree, and `.` means unchanged.
    private static func record(
        _ states: some StringProtocol,
        _ path: some StringProtocol,
        _ staged: inout [String],
        _ unstaged: inout [String],
    ) {
        let letters = Array(states)
        guard letters.count >= 2 else { return }
        if letters[0] != "." { staged.append(String(path)) }
        if letters[1] != "." { unstaged.append(String(path)) }
    }
}

/// A git command that reported a failure
public enum GitError: Error, Sendable, Equatable, LocalizedError, MCPErrorConvertible {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
            case let .commandFailed(output): "git failed: \(output)"
        }
    }

    public func toMCPError() -> MCPError { .internalError(errorDescription ?? "git failed") }
}
