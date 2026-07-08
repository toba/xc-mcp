import Foundation

/// Pure parsers for Mach-O command-line tool output (`otool`, `size`, `nm`, `lipo`) plus dyld-style
/// `@rpath` resolution. Kept free of subprocess/filesystem I/O so the string handling is
/// unit-testable with captured tool output; the caller supplies the raw output and a `fileExists`
/// probe.
///
/// Used by `analyze_app_bundle` to inspect a built app's main executable. Could also back raw
/// linker diagnostics for *failed* links (d6d-an4) since both need Mach-O/otool parsing.
public enum MachOInspector {
    /// A Mach-O segment and its file size.
    public struct Segment: Sendable, Equatable {
        public let name: String
        public let size: Int

        public init(name: String, size: Int) {
            self.name = name
            self.size = size
        }
    }

    /// A `LC_LOAD_DYLIB` dependency from `otool -L`.
    public struct LinkedLibrary: Sendable, Equatable {
        public let path: String

        public init(path: String) { self.path = path }

        /// True for `@rpath`/`@loader_path`/`@executable_path` deps (in-project, relocatable) as
        /// opposed to absolute system paths like `/usr/lib/libSystem.B.dylib`.
        public var isRelative: Bool {
            path.hasPrefix("@rpath/") || path.hasPrefix("@loader_path/")
                || path.hasPrefix("@executable_path/")
        }
    }

    // MARK: - Parsers

    /// Parses `size -m` output into segments, excluding `__PAGEZERO` (its 4GB vmsize otherwise
    /// skews any total). Segment lines look like `Segment __TEXT: 16384`; section lines are
    /// ignored.
    public static func parseSegments(_ output: String) -> [Segment] {
        var segments = [Segment]()

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let name = trimmed.stripping(prefix: "Segment "),
                  let colon = name.firstIndex(of: ":") else { continue }
            let segName = String(name[name.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard segName != "__PAGEZERO" else { continue }
            let sizeStr = name[name.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let size = Int(sizeStr) { segments.append(.init(name: segName, size: size)) }
        }
        return segments
    }

    /// Parses `otool -L` output into linked libraries. Dependency lines are tab-indented and carry
    /// a ` (compatibility version ...)` suffix; the leading `<path>:` header line is not indented.
    public static func parseLinkedLibraries(_ output: String) -> [LinkedLibrary] {
        var libs = [LinkedLibrary]()

        for line in output.components(separatedBy: .newlines) where line.hasPrefix("\t") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let path: String

            if let paren = trimmed.range(of: " (compatibility") {
                path = String(trimmed[trimmed.startIndex..<paren.lowerBound])
            } else {
                path = trimmed
            }
            if !path.isEmpty { libs.append(.init(path: path)) }
        }
        return libs
    }

    /// Parses `LC_RPATH` `path` entries from `otool -l` output.
    public static func parseRpaths(_ output: String) -> [String] {
        var rpaths = [String]()
        var inRpath = false

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "cmd LC_RPATH" {
                inRpath = true
            } else if inRpath, let value = trimmed.stripping(prefix: "path ") {
                // "path @loader_path/../Frameworks (offset 12)"
                var rp = value
                if let offset = rp.range(of: " (offset") {
                    rp = String(rp[rp.startIndex..<offset.lowerBound])
                }
                rpaths.append(rp.trimmingCharacters(in: .whitespaces))
                inRpath = false
            } else if trimmed.hasPrefix("cmd ") { inRpath = false }
        }
        return rpaths
    }

    /// Counts `_relinkableLibraryClasses` symbols in `nm` output — the mergeable-library merge
    /// marker.
    public static func countRelinkableClasses(_ nmOutput: String) -> Int {
        nmOutput.components(separatedBy: .newlines).count {
            $0.contains("_relinkableLibraryClasses")
        }
    }

    /// Parses `lipo -archs` output (a single space-separated line, e.g. `x86_64 arm64`).
    public static func parseArchitectures(_ output: String) -> [String] {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
    }

    // MARK: - dyld resolution

    /// dyld-style resolution of an `@rpath`/`@loader_path`/`@executable_path` dependency against
    /// the binary's `LC_RPATH` set: does it resolve to a file *inside the bundle*? Absolute rpaths
    /// (dev-time DerivedData `PackageFrameworks`) resolve outside the bundle and so are NOT counted
    /// — they mark the launchability gap.
    ///
    /// - Parameters:
    ///   - dep: The linked dependency (only `@`-relative deps can resolve inside a bundle).
    ///   - rpaths: `LC_RPATH` entries from the binary.
    ///   - appPath: The bundle root; a resolved path must live under it to count.
    ///   - executableDir: The main-executable directory (`@loader_path`/`@executable_path` for a
    ///     top-level executable).
    ///   - fileExists: Probe for whether a normalized absolute path exists on disk.
    public static func resolvesInsideBundle(
        dep: LinkedLibrary,
        rpaths: [String],
        appPath: String,
        executableDir: String,
        fileExists: (String) -> Bool,
    ) -> Bool {
        // For a top-level executable, @loader_path and @executable_path coincide.
        resolves(
            dep: dep,
            rpaths: rpaths,
            loaderDir: executableDir,
            executableDir: executableDir,
            appPath: appPath,
            fileExists: fileExists,
        )
    }

    /// dyld-style resolution generalized to any Mach-O in the bundle, distinguishing the loading
    /// image's directory (`@loader_path`) from the main executable's (`@executable_path`) — the two
    /// differ for an embedded framework.
    ///
    /// - Parameters:
    ///   - loaderDir: Directory of the image performing the load (`@loader_path`).
    ///   - executableDir: Directory of the main executable (`@executable_path`).
    public static func resolves(
        dep: LinkedLibrary,
        rpaths: [String],
        loaderDir: String,
        executableDir: String,
        appPath: String,
        fileExists: (String) -> Bool,
    ) -> Bool {
        let bundleRoot = (appPath as NSString).standardizingPath

        func existsInside(_ path: String) -> Bool {
            let norm = (path as NSString).standardizingPath
            return norm.hasPrefix(bundleRoot) && fileExists(norm)
        }

        let path = dep.path

        if let suffix = path.stripping(prefix: "@rpath/") {
            for rp in rpaths {
                let base = rp
                    .replacingOccurrences(of: "@executable_path", with: executableDir)
                    .replacingOccurrences(of: "@loader_path", with: loaderDir)
                if existsInside(base + "/" + suffix) { return true }
            }
            return false
        }
        if let suffix = path.stripping(prefix: "@loader_path/") {
            return existsInside(loaderDir + "/" + suffix)
        }

        if let suffix = path.stripping(prefix: "@executable_path/") {
            return existsInside(executableDir + "/" + suffix)
        }
        return false
    }

    // MARK: - Full-closure resolution

    /// A single Mach-O within a bundle (the main executable or an embedded framework binary)
    /// reduced to what dyld resolution needs: a display name, the directory it loads from
    /// (`@loader_path`), its own `LC_RPATH` set, and its relocatable (`@`-relative) dependencies.
    public struct MachOImage: Sendable, Equatable {
        public let name: String
        public let loaderDir: String
        public let rpaths: [String]
        public let relativeDeps: [LinkedLibrary]

        public init(
            name: String,
            loaderDir: String,
            rpaths: [String],
            relativeDeps: [LinkedLibrary]
        ) {
            self.name = name
            self.loaderDir = loaderDir
            self.rpaths = rpaths
            self.relativeDeps = relativeDeps
        }
    }

    /// A relocatable dependency that no image in the bundle can resolve to a file inside it,
    /// together with the images that reference it.
    public struct UnresolvedDep: Sendable, Equatable {
        public let dep: String
        public let referencedBy: [String]

        public init(dep: String, referencedBy: [String]) {
            self.dep = dep
            self.referencedBy = referencedBy
        }
    }

    /// Walks the full dependency closure — the main executable plus every embedded framework — and
    /// returns the `@rpath`/`@loader_path`/`@executable_path` dependencies that resolve to no file
    /// inside the bundle, each annotated with the images that reference it.
    ///
    /// This catches transitive framework-to-framework gaps that an app-binary-only scan misses: an
    /// embedded framework may link `@rpath/SomePackageProduct.framework/...` that is itself not
    /// embedded, so the bundle dyld-crashes standalone even though the app binary looks
    /// self-contained.
    ///
    /// dyld accumulates `LC_RPATH` entries along the whole load chain, so each image is resolved
    /// against its own rpaths unioned with the main executable's — the standard app +
    /// `Contents/ Frameworks` layout where the executable owns the `@executable_path/../Frameworks`
    /// search path.
    ///
    /// - Parameters:
    ///   - images: The main executable followed by each embedded framework binary.
    ///   - executableDir: Directory of the main executable (`@executable_path`).
    ///   - executableRpaths: The main executable's `LC_RPATH` set (folded into every image's
    ///     search).
    ///   - appPath: The bundle root; a resolved path must live under it to count.
    ///   - fileExists: Probe for whether a normalized absolute path exists on disk.
    /// - Returns: Unresolved deps in first-seen order, each with its referencing images sorted.
    public static func unresolvedClosure(
        images: [MachOImage],
        executableDir: String,
        executableRpaths: [String],
        appPath: String,
        fileExists: (String) -> Bool,
    ) -> [UnresolvedDep] {
        var referrers = [String: Set<String>]()
        var order = [String]()

        for image in images {
            var effectiveRpaths = executableRpaths
            for rp in image.rpaths where !effectiveRpaths.contains(rp) {
                effectiveRpaths.append(rp)
            }

            for dep in image.relativeDeps {
                let resolved = resolves(
                    dep: dep,
                    rpaths: effectiveRpaths,
                    loaderDir: image.loaderDir,
                    executableDir: executableDir,
                    appPath: appPath,
                    fileExists: fileExists,
                )

                if !resolved {
                    if referrers[dep.path] == nil { order.append(dep.path) }
                    referrers[dep.path, default: []].insert(image.name)
                }
            }
        }

        return order.map { UnresolvedDep(dep: $0, referencedBy: referrers[$0]!.sorted()) }
    }
}

private extension String {
    /// Returns the remainder after `prefix`, or nil if the string does not start with it.
    func stripping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
