import Foundation

/// Finds the index store a Swift package build wrote
///
/// The store path depends on the build system. swift-build, the default since Swift 6.4, roots the
/// store at `.build/out`. The native build system writes `.build/<configuration>/index/store`
/// instead. Both layouts keep their records under a `v5` directory, and that directory is what
/// separates a populated store from an empty one.
///
/// A scanner that hard-codes one layout fails on a package the other one built, so resolve the path
/// at run time:
///
/// ```swift
/// let store = IndexStoreLocator.locate(packagePath: path)
/// if store.exists { arguments.append(contentsOf: ["--index-store-path", store.path]) }
/// ```
public enum IndexStoreLocator {
    /// The index store a scanner reads, and whether a build has populated it
    public struct Location: Sendable, Equatable {
        /// Absolute path to the store directory.
        public let path: String

        /// True when the directory holds indexed records.
        public let exists: Bool

        public init(path: String, exists: Bool) {
            self.path = path
            self.exists = exists
        }
    }

    /// The directory the current index store format writes its records into.
    private static let recordsDirectory = "v5"

    /// The store paths searched under a package, newest layout first.
    ///
    /// - Parameters:
    ///   - packagePath: The package root, the directory that holds `Package.swift`.
    ///   - configuration: The build configuration the store belongs to.
    /// - Returns: Absolute paths, whether or not they exist.
    public static func candidates(
        packagePath: String,
        configuration: String = "debug",
    ) -> [String] {
        [
            buildDirectory(packagePath: packagePath).appendingPathComponent("out").path,
            fallbackPath(packagePath: packagePath, configuration: configuration),
        ]
    }

    /// The path to name when a build has to be told where to write its store.
    ///
    /// This is the native build system's own default, so a build that writes here leaves the
    /// package in a layout every Swift toolchain since 5.x understands.
    ///
    /// - Parameters:
    ///   - packagePath: The package root, the directory that holds `Package.swift`.
    ///   - configuration: The build configuration the store belongs to.
    public static func fallbackPath(
        packagePath: String,
        configuration: String = "debug",
    ) -> String {
        buildDirectory(packagePath: packagePath)
            .appendingPathComponent("\(configuration)/index/store").path
    }

    /// Locates the index store for a package.
    ///
    /// - Parameters:
    ///   - packagePath: The package root, the directory that holds `Package.swift`.
    ///   - configuration: The build configuration the store belongs to.
    /// - Returns: The first candidate that holds records. When no candidate does, the result names
    ///   ``fallbackPath(packagePath:configuration:)`` and reports `exists` as false.
    public static func locate(
        packagePath: String,
        configuration: String = "debug",
    ) -> Location {
        for candidate in candidates(packagePath: packagePath, configuration: configuration)
            where isPopulated(candidate)
        {
            return Location(path: candidate, exists: true)
        }
        return .init(
            path: fallbackPath(packagePath: packagePath, configuration: configuration),
            exists: false,
        )
    }

    /// True when the directory holds index records a scanner can read.
    ///
    /// The check reads the unit files rather than the records directory that holds them. A
    /// cancelled build leaves the directory behind with nothing in it, and a scanner that reads an
    /// empty store reports every declaration in the package as unused.
    private static func isPopulated(_ path: String) -> Bool {
        let units = (path as NSString).appendingPathComponent("\(recordsDirectory)/units")
        let entries = try? FileManager.default.contentsOfDirectory(atPath: units)
        return entries?.isEmpty == false
    }

    private static func buildDirectory(packagePath: String) -> URL {
        URL(fileURLWithPath: (packagePath as NSString).expandingTildeInPath)
            .appendingPathComponent(".build")
    }
}
