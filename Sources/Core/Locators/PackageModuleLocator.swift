import Foundation

/// Finds the directories a Swift package build writes `.swiftmodule` files into
///
/// SwiftPM compiles the package's own targets and every dependency it builds into one directory per
/// configuration, so a single directory covers both. The layout depends on the build system. The
/// native build system writes `.build/<triple>/<config>/Modules`, and swift-build writes
/// `.build/out/Products/<Config>` with a `.build/<config>` symlink to it. A caller passes each
/// directory to the compiler as an `-I` search path.
public enum PackageModuleLocator {
    /// The `.build` children that never hold the modules of a completed build.
    ///
    /// `index-build` is skipped because SourceKit-LSP compiles those modules with skipped function
    /// bodies, and they shadow the real build output.
    private static let skippedChildren: Set<String> = [
        "checkouts", "repositories", "artifacts", "plugins", "index-build",
    ]

    /// The configurations searched when the caller names none.
    public static let defaultConfigurations = ["debug", "release"]

    /// The module search directories under a package, newest first.
    ///
    /// A directory left by an older toolchain holds modules the current compiler refuses to load,
    /// so the order decides whether the extraction succeeds. The most recently written directory
    /// wins.
    ///
    /// - Parameters:
    ///   - packagePath: The package root, the directory that holds `Package.swift`.
    ///   - configurations: The build configurations to look for.
    /// - Returns: Absolute paths, each holding at least one `.swiftmodule`. Empty when the package
    ///   has no build output.
    public static func searchPaths(
        packagePath: String,
        configurations: [String] = defaultConfigurations,
    ) -> [String] {
        let fm = FileManager.default
        let buildDir = URL(fileURLWithPath: (packagePath as NSString).expandingTildeInPath)
            .appendingPathComponent(".build")
        guard fm.fileExists(atPath: buildDir.path) else { return [] }

        var roots = [buildDir]

        for name in (try? fm.contentsOfDirectory(atPath: buildDir.path)) ?? []
            where !skippedChildren.contains(name) && !name.hasPrefix(".")
        {
            let child = buildDir.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            roots.append(child)
        }

        var seen: Set<String> = []
        var found: [(path: String, date: Date)] = []

        for root in roots {
            for configuration in configurations {
                for candidate in candidates(in: root, configuration: configuration) {
                    let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
                    guard seen.insert(resolved.path).inserted,
                          let entries = try? fm.contentsOfDirectory(atPath: resolved.path),
                          entries.contains(where: { $0.hasSuffix(".swiftmodule") })
                    else { continue }
                    let attributes = try? fm.attributesOfItem(atPath: resolved.path)
                    let date = attributes?[.modificationDate] as? Date
                    found.append((resolved.path, date ?? .distantPast))
                }
            }
        }
        return found.sorted { $0.date > $1.date }.map(\.path)
    }

    /// The directory shapes a build system writes modules into, under one `.build` root.
    private static func candidates(in root: URL, configuration: String) -> [URL] {
        let configured = root.appendingPathComponent(configuration)
        return [
            configured,
            configured.appendingPathComponent("Modules"),
            root.appendingPathComponent("Products")
                .appendingPathComponent(configuration.capitalized),
        ]
    }
}
