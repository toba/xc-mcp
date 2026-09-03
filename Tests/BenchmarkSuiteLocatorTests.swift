import MCP
import Testing
import Foundation
@testable import XCMCPCore

/// Tests for finding the directory a `swift package benchmark` command runs from.
///
/// A nested suite is the normal shape and an application that declares the plugin in its root
/// manifest is the exception, so the locator has to tell one from the other.
@Suite(.temporaryDirectory)
struct BenchmarkSuiteLocatorTests {
    /// A manifest that declares the benchmark plugin, which is what the locator looks for
    private static let withPlugin = """
        // swift-tools-version: 6.4
        import PackageDescription

        let package = Package(
            name: "probe",
            targets: [
                .executableTarget(
                    name: "ProbeBenchmarks",
                    plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
                )
            ]
        )
        """

    /// A manifest with no benchmark target
    private static let withoutPlugin = """
        // swift-tools-version: 6.4
        import PackageDescription

        let package = Package(name: "probe", targets: [.target(name: "Probe")])
        """

    /// Creates a package in the test's own temporary directory and returns its path.
    private func makePackage(manifest: String, nested: String? = nil) throws -> String {
        let root = TemporaryDirectory.url
        try Data(manifest.utf8).write(to: root.appendingPathComponent("Package.swift"))

        if let nested {
            let directory = root.appendingPathComponent("Benchmarks")
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
            )
            try Data(nested.utf8).write(to: directory.appendingPathComponent("Package.swift"))
        }
        return root.path
    }

    @Test
    func `a nested suite is the directory the command runs from`() throws {
        let root = try makePackage(manifest: Self.withoutPlugin, nested: Self.withPlugin)
        let location = try BenchmarkSuiteLocator.locate(packagePath: root)

        #expect(location.isNested)
        #expect(location.path == root + "/Benchmarks")
        #expect(location.label.contains("nested"))
    }

    @Test
    func `a root manifest that declares the plugin is the fallback`() throws {
        let root = try makePackage(manifest: Self.withPlugin)
        let location = try BenchmarkSuiteLocator.locate(packagePath: root)

        #expect(!location.isNested)
        #expect(location.path == root)
        #expect(location.label == "the root package")
    }

    @Test
    func `a nested suite wins over a root manifest that also declares the plugin`() throws {
        let root = try makePackage(manifest: Self.withPlugin, nested: Self.withPlugin)

        #expect(try BenchmarkSuiteLocator.locate(packagePath: root).isNested)
    }

    @Test
    func `a nested directory with no plugin falls back to the root`() throws {
        let root = try makePackage(manifest: Self.withPlugin, nested: Self.withoutPlugin)
        let location = try BenchmarkSuiteLocator.locate(packagePath: root)

        #expect(!location.isNested)
        #expect(location.path == root)
    }

    @Test
    func `a package with no suite is refused`() throws {
        let root = try makePackage(manifest: Self.withoutPlugin)

        #expect(throws: MCPError.self) { try BenchmarkSuiteLocator.locate(packagePath: root) }
    }

    // MARK: - Recorded benchmarks

    /// Writes empty threshold files into the test's own suite directory and returns its path.
    private func makeThresholds(_ files: [String]) throws -> String {
        let suite = TemporaryDirectory.url
        let directory = suite.appendingPathComponent("Thresholds")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for file in files { try Data("{}".utf8).write(to: directory.appendingPathComponent(file)) }
        return suite.path
    }

    @Test
    func `the threshold files name the benchmarks of each target`() throws {
        let suite = try makeThresholds([
            "TobaCoreBenchmarks.TokenizeTitle.p90.json",
            "TobaCoreBenchmarks.HexStringFromData.p90.json",
            "TobaHashBenchmarks.HashOneBlock.p90.json",
        ])
        let recorded = BenchmarkSuiteLocator.recordedBenchmarks(suitePath: suite)

        #expect(recorded.count == 2)
        #expect(recorded.first?.target == "TobaCoreBenchmarks")
        #expect(recorded.first?.benchmarks == ["HexStringFromData", "TokenizeTitle"])
        #expect(recorded.last?.benchmarks == ["HashOneBlock"])
    }

    @Test
    func `two percentiles of one benchmark name it once`() throws {
        let suite = try makeThresholds(["Bench.OneName.p50.json", "Bench.OneName.p90.json"])

        #expect(
            BenchmarkSuiteLocator.recordedBenchmarks(suitePath: suite).first?
                .benchmarks
                == ["OneName"],
        )
    }

    @Test
    func `a benchmark name holding a dot stays whole`() throws {
        let suite = try makeThresholds(["Bench.Decode.JSON.p90.json"])

        #expect(
            BenchmarkSuiteLocator.recordedBenchmarks(suitePath: suite).first?
                .benchmarks
                == ["Decode.JSON"],
        )
    }

    @Test
    func `a suite with no thresholds directory records nothing`() {
        #expect(
            BenchmarkSuiteLocator.recordedBenchmarks(suitePath: TemporaryDirectory.path).isEmpty)
    }

    @Test
    func `a file that is not a threshold is ignored`() throws {
        let suite = try makeThresholds(["README.md", "Bench.json"])

        #expect(BenchmarkSuiteLocator.recordedBenchmarks(suitePath: suite).isEmpty)
    }
}
