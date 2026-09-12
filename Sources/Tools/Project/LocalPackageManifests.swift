import XcodeProj
import Foundation

/// The kind of product a package manifest declares
enum PackageProductKind: String { case library, plugin }

/// Reads the `Package.swift` manifests of the local packages an Xcode project references
enum LocalPackageManifests {
    /// A package directory paired with the text of its manifest
    struct Manifest {
        let directory: String
        let contents: String
    }

    /// Resolves every `XCLocalSwiftPackageReference` in the project to a directory that exists on
    /// disk
    ///
    /// Xcode stores the reference relative to the project directory, so a relative path resolves
    /// against `projectDir` rather than against the working directory.
    ///
    /// - Parameters:
    ///   - xcodeproj: The loaded project holding the references.
    ///   - projectDir: The directory holding the `.xcodeproj` bundle.
    static func directories(in xcodeproj: XcodeProj, projectDir: String) -> [String] {
        guard let project = xcodeproj.pbxproj.rootObject else { return [] }
        let projectDirURL = URL(filePath: projectDir)

        return project.localPackages.compactMap { local in
            let relative = local.relativePath
            let resolved = relative.hasPrefix("/")
                ? URL(filePath: relative).standardized.path
                : projectDirURL.appending(path: relative).standardized.path
            return FileManager.default.fileExists(atPath: resolved) ? resolved : nil
        }
    }

    /// Reads the manifest of each directory once, skipping a directory that holds none
    static func manifests(in directories: some Sequence<String>) -> [Manifest] {
        directories.compactMap { directory in
            guard let contents = read(directory: directory) else { return nil }
            return Manifest(directory: directory, contents: contents)
        }
    }

    /// Reads the `Package.swift` of one directory, or nil when the directory holds none
    static func read(directory: String) -> String? {
        try? String(contentsOfFile: directory + "/Package.swift", encoding: .utf8)
    }

    /// Returns the kind of the product `productName` that `packageSwift` declares, or nil when it
    /// declares no product of that name
    ///
    /// An executable reads as a library, because a consumer links the two the same way.
    static func productKind(
        of productName: String,
        in packageSwift: String,
    ) -> PackageProductKind? {
        let escaped = NSRegularExpression.escapedPattern(for: productName)
        let patterns: [(String, PackageProductKind)] = [
            (#"\.plugin\s*\(\s*name:\s*"\#(escaped)""#, .plugin),
            (#"\.library\s*\(\s*name:\s*"\#(escaped)""#, .library),
            (#"\.executable\s*\(\s*name:\s*"\#(escaped)""#, .library),
        ]

        for (
            pattern, kind
        ) in patterns
            where packageSwift.range(of: pattern, options: .regularExpression) != nil
        { return kind }
        return nil
    }

    /// Reports whether any manifest declares a product named `productName`
    static func declaresProduct(_ productName: String, inAnyOf manifests: [Manifest]) -> Bool {
        manifests.contains { productKind(of: productName, in: $0.contents) != nil }
    }
}
