import Testing
import Foundation
@testable import XCMCPCore

/// Tests for the `swift build` and `swift test` argument lists, which are the whole surface a
/// release test run and a compiler probe reach.
struct SwiftRunnerArgumentTests {
    /// Returns the argument that follows `flag`, or `nil` when the flag is absent.
    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// Returns true when `pair` appears as two adjacent arguments.
    private func contains(_ pair: (String, String), in args: [String]) -> Bool {
        for index in args.indices.dropLast()
            where args[index] == pair.0 && args[index + 1] == pair.1
        { return true }
        return false
    }

    // MARK: - Testability

    @Test
    func `a release build of the test targets asks for testability`() {
        let args = SwiftRunner.buildArguments(configuration: "release", buildTests: true)

        #expect(args.contains("--build-tests"))
        #expect(contains(("-Xswiftc", "-enable-testing"), in: args))
    }

    @Test
    func `a debug build of the test targets leaves testability to SwiftPM`() {
        let args = SwiftRunner.buildArguments(configuration: "debug", buildTests: true)

        #expect(args.contains("--build-tests"))
        #expect(!args.contains("-enable-testing"))
    }

    @Test
    func `a release build without test targets does not ask for testability`() {
        let args = SwiftRunner.buildArguments(configuration: "release")

        #expect(!args.contains("-enable-testing"))
    }

    @Test
    func `a release test run asks for testability`() {
        let args = SwiftRunner.testArguments(configuration: "release")

        #expect(value(after: "-c", in: args) == "release")
        #expect(contains(("-Xswiftc", "-enable-testing"), in: args))
    }

    // MARK: - Configuration

    @Test
    func `a test run defaults to debug and names the configuration explicitly`() {
        let args = SwiftRunner.testArguments()

        #expect(value(after: "-c", in: args) == "debug")
        #expect(!args.contains("-enable-testing"))
    }

    @Test
    func `a filtered release test run carries both the filter and the configuration`() {
        let args = SwiftRunner.testArguments(configuration: "release", filter: "SharingPermissions")

        #expect(value(after: "-c", in: args) == "release")
        #expect(value(after: "--filter", in: args) == "SharingPermissions")
    }

    // MARK: - Compiler flags

    @Test
    func `each compiler flag gets its own -Xswiftc`() {
        let args = SwiftRunner.buildArguments(swiftcFlags: [
            "-Xllvm", "-opt-bisect-limit=999999999", "-num-threads", "1",
        ],)

        #expect(contains(("-Xswiftc", "-Xllvm"), in: args))
        #expect(contains(("-Xswiftc", "-opt-bisect-limit=999999999"), in: args))
        #expect(contains(("-Xswiftc", "-num-threads"), in: args))
        #expect(contains(("-Xswiftc", "1"), in: args))
    }

    @Test
    func `a test run forwards compiler flags too`() {
        let args = SwiftRunner.testArguments(swiftcFlags: ["-Xllvm", "-inline-threshold=0"])

        #expect(contains(("-Xswiftc", "-Xllvm"), in: args))
        #expect(contains(("-Xswiftc", "-inline-threshold=0"), in: args))
    }

    @Test
    func `no compiler flags leaves the argument list untouched`() {
        #expect(!SwiftRunner.buildArguments().contains("-Xswiftc"))
        #expect(!SwiftRunner.testArguments().contains("-Xswiftc"))
    }

    // MARK: - Saved temporaries

    @Test
    func `a crash rerun keeps the driver temporaries`() {
        let args = SwiftRunner.buildArguments(verbose: true, saveTemps: true)

        #expect(args.contains("-v"))
        #expect(contains(("-Xswiftc", "-save-temps"), in: args))
    }

    @Test
    func `an ordinary build does not keep the driver temporaries`() {
        #expect(!SwiftRunner.buildArguments().contains("-save-temps"))
    }
}
