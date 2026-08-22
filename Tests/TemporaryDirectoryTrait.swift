import Testing
import Foundation

/// A unique temporary directory that exists for the duration of a single test.
///
/// Read the directory with ``TemporaryDirectory/url``. The value is a task local, so each test sees
/// its own directory even when the suite runs in parallel.
enum TemporaryDirectory {
    @TaskLocal fileprivate static var current: URL?

    /// The directory created for the running test.
    ///
    /// - Precondition: the test or its suite carries the `.temporaryDirectory` trait.
    static var url: URL {
        guard let current else {
            preconditionFailure(
                "TemporaryDirectory.url requires the .temporaryDirectory trait on the test or its suite",
            )
        }
        return current
    }

    /// The path of ``TemporaryDirectory/url``.
    static var path: String { url.path }
}

/// Creates ``TemporaryDirectory/url`` before a test runs and removes it afterwards.
///
/// Apply the trait to a suite to give every test in that suite its own directory. Tests that write
/// to disk then stay isolated from each other, and no test leaks a directory.
///
/// ```swift
/// @Suite(.temporaryDirectory)
/// struct MyToolTests {
///     @Test
///     func `Writes the project`() throws {
///         let projectPath = Path(TemporaryDirectory.path) + "Test.xcodeproj"
///         // ...
///     }
/// }
/// ```
struct TemporaryDirectoryTrait: TestTrait, SuiteTrait, TestScoping {
    /// Applies the trait to each test in a suite, not to the suite as a whole.
    var isRecursive: Bool { true }

    /// Scopes each test case, never the suite.
    ///
    /// The type conforms to both `TestTrait` and `SuiteTrait`, and those protocols supply different
    /// defaults. The explicit implementation removes the ambiguity.
    func scopeProvider(for _: Test, testCase: Test.Case?) -> Self? { testCase == nil ? nil : self }

    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void,
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try await TemporaryDirectory.$current.withValue(directory) { try await function() }
    }
}

extension Trait where Self == TemporaryDirectoryTrait {
    /// Gives the test its own temporary directory and removes the directory afterwards.
    static var temporaryDirectory: Self { .init() }
}
