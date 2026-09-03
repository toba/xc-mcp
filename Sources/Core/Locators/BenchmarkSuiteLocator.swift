import MCP
import Foundation

/// Finds the package directory a `swift package benchmark` command runs from
///
/// A suite is normally a nested package at `<repo>/Benchmarks`, which is its own resolution root,
/// so the command runs from there and not from the repository root. An application may instead name
/// the benchmark dependencies in its own root manifest, and then the root is the directory.
public enum BenchmarkSuiteLocator {
    /// The directory name a nested suite uses
    public static let nestedDirectory = "Benchmarks"

    /// The plugin a manifest declares to get the `benchmark` verb
    static let pluginName = "BenchmarkPlugin"

    /// One resolved suite location
    public struct Location: Sendable, Equatable {
        /// The directory the command runs from
        public let path: String

        /// Whether the suite is a nested package rather than the root one
        public let isNested: Bool

        public init(path: String, isNested: Bool) {
            self.path = path
            self.isNested = isNested
        }

        /// A label for a tool result, naming which package carries the suite
        public var label: String {
            isNested
                ? "the nested \(BenchmarkSuiteLocator.nestedDirectory) package"
                : "the root package"
        }
    }

    /// Resolves the directory the plugin runs from.
    ///
    /// - Parameter packagePath: The repository's own package directory.
    /// - Returns: The nested suite when one exists, otherwise the root package.
    /// - Throws: ``MCPError/invalidParams(_:)`` when neither manifest declares the plugin.
    public static func locate(packagePath: String) throws(MCPError) -> Location {
        let nested = URL(fileURLWithPath: packagePath)
            .appendingPathComponent(nestedDirectory).path

        if declaresPlugin(at: nested) { return Location(path: nested, isNested: true) }
        if declaresPlugin(at: packagePath) { return Location(path: packagePath, isNested: false) }

        throw .invalidParams(
            "No benchmark suite at \(packagePath). A suite is a nested package at "
                + "\(nestedDirectory)/ whose manifest declares \(pluginName), and an application may "
                + "declare it in the root manifest instead. Neither manifest here declares it.",
        )
    }

    /// The directory a suite keeps its recorded ceilings in
    public static let thresholdsDirectory = "Thresholds"

    /// The benchmark names the suite records a ceiling for, read off disk.
    ///
    /// The plugin writes one file per benchmark, named `<Target>.<Benchmark>.<percentile>.json`, so
    /// one directory read names the benchmarks without building the suite. A benchmark with no
    /// recorded ceiling yet is absent from the result, which is why a caller has to say where the
    /// names came from.
    ///
    /// - Parameter suitePath: The directory the plugin runs from.
    /// - Returns: One entry per target, in name order. Empty when the directory is absent or holds
    ///   no threshold file.
    public static func recordedBenchmarks(suitePath: String) -> [BenchmarkListing] {
        let directory = URL(fileURLWithPath: suitePath)
            .appendingPathComponent(thresholdsDirectory).path
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }

        var order: [String] = []
        var byTarget: [String: [String]] = [:]
        // one benchmark writes one file per percentile, so the same name arrives several times
        var seen: Set<String> = []

        for file in files.sorted() where file.hasSuffix(".json") {
            let parts = file.dropLast(".json".count).split(separator: ".")
            // target, then the benchmark name, then the percentile the file records
            guard parts.count >= 3 else { continue }
            let target = String(parts[0])
            let benchmark = parts.dropFirst().dropLast().joined(separator: ".")
            guard seen.insert("\(target)\u{0}\(benchmark)").inserted else { continue }

            if byTarget[target] == nil { order.append(target) }
            byTarget[target, default: []].append(benchmark)
        }
        return order.map { BenchmarkListing(target: $0, benchmarks: byTarget[$0] ?? []) }
    }

    /// Whether the manifest in `directory` declares the benchmark plugin.
    ///
    /// Reading the text is enough, because the plugin name is the token SwiftPM matches and a
    /// manifest that omits it has no `benchmark` verb to invoke.
    private static func declaresPlugin(at directory: String) -> Bool {
        let manifest = URL(fileURLWithPath: directory)
            .appendingPathComponent("Package.swift")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return false }
        return text.contains(pluginName)
    }
}
