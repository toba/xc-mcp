import Foundation

/// Pure parsers for Mach-O command-line tool output (`otool`, `size`, `nm`, `lipo`) plus dyld-style
/// `@rpath` resolution. Kept free of subprocess/filesystem I/O so the string handling is unit-testable
/// with captured tool output; the caller supplies the raw output and a `fileExists` probe.
///
/// Used by `analyze_app_bundle` to inspect a built app's main executable. Could also back raw linker
/// diagnostics for *failed* links (d6d-an4) since both need Mach-O/otool parsing.
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

    /// Parses `size -m` output into segments, excluding `__PAGEZERO` (its 4GB vmsize otherwise skews
    /// any total). Segment lines look like `Segment __TEXT: 16384`; section lines are ignored.
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

    /// Parses `otool -L` output into linked libraries. Dependency lines are tab-indented and carry a
    /// ` (compatibility version ...)` suffix; the leading `<path>:` header line is not indented.
    public static func parseLinkedLibraries(_ output: String) -> [LinkedLibrary] {
        var libs = [LinkedLibrary]()
        for line in output.components(separatedBy: .newlines) {
            guard line.hasPrefix("\t") else { continue }
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
                if let offset = rp.range(of: " (offset") { rp = String(rp[rp.startIndex..<offset.lowerBound]) }
                rpaths.append(rp.trimmingCharacters(in: .whitespaces))
                inRpath = false
            } else if trimmed.hasPrefix("cmd ") {
                inRpath = false
            }
        }
        return rpaths
    }

    /// Counts `_relinkableLibraryClasses` symbols in `nm` output — the mergeable-library merge marker.
    public static func countRelinkableClasses(_ nmOutput: String) -> Int {
        nmOutput.components(separatedBy: .newlines).count { $0.contains("_relinkableLibraryClasses") }
    }

    /// Parses `lipo -archs` output (a single space-separated line, e.g. `x86_64 arm64`).
    public static func parseArchitectures(_ output: String) -> [String] {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
    }

    // MARK: - dyld resolution

    /// dyld-style resolution of an `@rpath`/`@loader_path`/`@executable_path` dependency against the
    /// binary's `LC_RPATH` set: does it resolve to a file *inside the bundle*? Absolute rpaths
    /// (dev-time DerivedData `PackageFrameworks`) resolve outside the bundle and so are NOT counted —
    /// they mark the launchability gap.
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
                    .replacingOccurrences(of: "@loader_path", with: executableDir)
                if existsInside(base + "/" + suffix) { return true }
            }
            return false
        }
        if let suffix = path.stripping(prefix: "@loader_path/") {
            return existsInside(executableDir + "/" + suffix)
        }
        if let suffix = path.stripping(prefix: "@executable_path/") {
            return existsInside(executableDir + "/" + suffix)
        }
        return false
    }
}

private extension String {
    /// Returns the remainder after `prefix`, or nil if the string does not start with it.
    func stripping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
