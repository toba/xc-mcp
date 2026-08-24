import MCP
import Testing
import Foundation
@testable import XCMCPCore

/// Covers the SwiftPM trait set the `swift build` and `swift test` invocations carry.
///
/// A package that declares a trait with no default compiles only its trait-off half until a command
/// names the trait, and the command still reports success. These tests hold the flag, the label and
/// the session resolution that make the trait-on half reachable.
@Suite(.temporaryDirectory, .serialized)
struct SwiftBuildTraitsTests {
    private func makeTempPath() -> URL {
        TemporaryDirectory.url.appendingPathComponent("xc-mcp-traits-test.json")
    }

    private func makeManager(_ path: URL) -> SessionManager {
        .init(filePath: path, enableWarmup: false)
    }

    // MARK: - Parsing

    @Test
    func `Omitting both trait arguments parses as nil`() throws {
        #expect(try SwiftBuildTraits.parse(from: ["configuration": .string("debug")]) == nil)
    }

    @Test
    func `A traits array parses as the named set and drops duplicates`() throws {
        let parsed = try SwiftBuildTraits.parse(from: [
            "traits": .array([.string("defaults"), .string("DataTesting"), .string("defaults")])
        ])

        #expect(parsed == .named(["defaults", "DataTesting"]))
    }

    @Test
    func `An empty traits array selects the package defaults`() throws {
        #expect(try SwiftBuildTraits.parse(from: ["traits": .array([])]) == .packageDefault)
    }

    @Test
    func `enable_all_traits parses as the all case`() throws {
        #expect(try SwiftBuildTraits.parse(from: ["enable_all_traits": .bool(true)]) == .all)
    }

    @Test
    func `A false enable_all_traits selects the package defaults`() throws {
        #expect(
            try SwiftBuildTraits.parse(from: ["enable_all_traits": .bool(false)]
            )
                == .packageDefault,
        )
    }

    @Test
    func `Both trait arguments together are refused with an error naming both`() {
        let arguments: [String: Value] = [
            "traits": .array([.string("DataTesting")]),
            "enable_all_traits": .bool(true),
        ]

        #expect(throws: MCPError.self) { try SwiftBuildTraits.parse(from: arguments) }

        do {
            _ = try SwiftBuildTraits.parse(from: arguments)
            Issue.record("Expected an invalidParams error")
        } catch let error as MCPError {
            #expect("\(error)".contains("`traits`"))
            #expect("\(error)".contains("`enable_all_traits`"))
        } catch {
            Issue.record("Expected an MCPError, got \(error)")
        }
    }

    // MARK: - Flags

    @Test
    func `The package default set adds no flag`() {
        #expect(SwiftBuildTraits.packageDefault.arguments.isEmpty)
    }

    @Test
    func `A named set becomes one comma separated traits flag`() {
        let arguments = SwiftBuildTraits.named(["defaults", "DataTesting"]).arguments

        #expect(arguments == ["--traits", "defaults,DataTesting"])
    }

    @Test
    func `The all case becomes enable-all-traits`() {
        #expect(SwiftBuildTraits.all.arguments == ["--enable-all-traits"])
    }

    // MARK: - Labels

    @Test
    func `Every trait set carries a non-empty label`() {
        #expect(SwiftBuildTraits.packageDefault.label == "default traits")
        #expect(SwiftBuildTraits.named(["DataTesting"]).label == "traits DataTesting")
        #expect(SwiftBuildTraits.all.label == "all traits")
    }

    @Test
    func `A named set that drops the defaults token warns about it`() throws {
        let warning = try #require(SwiftBuildTraits.named(["DataTesting"]).replacedDefaultsWarning)

        #expect(warning.contains("defaults"))
    }

    @Test
    func `A named set that keeps the defaults token warns about nothing`() {
        #expect(SwiftBuildTraits.named(["defaults", "DataTesting"]).replacedDefaultsWarning == nil)
        #expect(SwiftBuildTraits.packageDefault.replacedDefaultsWarning == nil)
        #expect(SwiftBuildTraits.all.replacedDefaultsWarning == nil)
    }

    // MARK: - Argument lists

    @Test
    func `A build with a named trait set passes the traits flag`() {
        let args = SwiftRunner.buildArguments(traits: .named(["defaults", "DataTesting"]))

        #expect(args.contains("--traits"))
        #expect(args.contains("defaults,DataTesting"))
    }

    @Test
    func `A test run with the all case passes enable-all-traits`() {
        #expect(SwiftRunner.testArguments(traits: .all).contains("--enable-all-traits"))
    }

    @Test
    func `Omitting the trait set leaves the build invocation as it was`() {
        let withDefault = SwiftRunner.buildArguments(traits: .packageDefault)

        #expect(withDefault == SwiftRunner.buildArguments())
        #expect(!withDefault.contains("--traits"))
        #expect(!withDefault.contains("--enable-all-traits"))
    }

    @Test
    func `Omitting the trait set leaves the test invocation as it was`() {
        let withDefault = SwiftRunner.testArguments(traits: .packageDefault)

        #expect(withDefault == SwiftRunner.testArguments())
        #expect(!withDefault.contains("--traits"))
        #expect(!withDefault.contains("--enable-all-traits"))
    }

    // MARK: - Session resolution

    @Test
    func `traits persist to disk and load in a new instance`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(traits: ["defaults", "DataTesting"])

        let reloaded = makeManager(path)
        let defaults = await reloaded.getDefaults()
        #expect(defaults.traits == ["defaults", "DataTesting"])
    }

    @Test
    func `An empty traits array clears the persisted list`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(traits: ["DataTesting"])
        await manager.setDefaults(traits: [])

        let defaults = await manager.getDefaults()
        #expect(defaults.traits == nil)
    }

    @Test
    func `resolveTraits falls back to the session default when both keys are absent`() async throws
    {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(traits: ["DataTesting"])

        #expect(try await manager.resolveTraits(from: [:]) == .named(["DataTesting"]))
    }

    @Test
    func `resolveTraits returns the package default when nothing is configured`() async throws {
        let path = makeTempPath()

        let manager = makeManager(path)
        #expect(try await manager.resolveTraits(from: [:]) == .packageDefault)
    }

    @Test
    func `A per-invocation traits array replaces the session default`() async throws {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(traits: ["DataTesting"])

        let arguments: [String: Value] = ["traits": .array([.string("Experimental")])]
        #expect(try await manager.resolveTraits(from: arguments) == .named(["Experimental"]))

        // The persisted default survives the per-call override.
        #expect(try await manager.resolveTraits(from: [:]) == .named(["DataTesting"]))
    }

    @Test
    func `An empty per-invocation traits array suppresses the session default`() async throws {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(traits: ["DataTesting"])

        let arguments: [String: Value] = ["traits": .array([])]
        #expect(try await manager.resolveTraits(from: arguments) == .packageDefault)
    }

    @Test
    func `clear removes the session traits`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(traits: ["DataTesting"])
        await manager.clear()

        let defaults = await manager.getDefaults()
        #expect(defaults.traits == nil)
    }

    @Test
    func `The session summary names the trait set either way`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        #expect(await manager.summary().contains("Package traits: (package defaults)"))

        await manager.setDefaults(traits: ["defaults", "DataTesting"])
        #expect(await manager.summary().contains("Package traits: defaults, DataTesting"))
    }
}
