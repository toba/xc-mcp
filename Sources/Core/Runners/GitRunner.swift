import Foundation

/// Reads tags from a git remote.
///
/// `show_package_resolution` needs the newest tag a package repository publishes so it can say why
/// resolution kept an older version. `git ls-remote --tags` answers that without cloning.
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
}
