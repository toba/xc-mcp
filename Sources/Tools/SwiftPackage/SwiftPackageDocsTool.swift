import MCP
import XCMCPCore
import Foundation

/// Builds a DocC catalog for a Swift package and reports the compiler diagnostics.
///
/// The tool drives the toolchain `docc` binary against a symbol graph SwiftPM emits, so a package
/// does not need the `swift-docc-plugin` dependency in its manifest.
public struct SwiftPackageDocsTool: Sendable {
    /// Access levels `swift package dump-symbol-graph --minimum-access-level` accepts.
    static let accessLevels = ["private", "fileprivate", "internal", "package", "public", "open"]

    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = .init(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "swift_package_docs",
            description:
                "Build a DocC catalog for a Swift package and report the documentation diagnostics grouped by article. Emits a symbol graph with SwiftPM and runs the toolchain docc binary, so the package needs no swift-docc-plugin dependency.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified.",
                        ),
                    ]),
                    "catalog_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to one .docc catalog to build. Defaults to every catalog found in the package.",
                        ),
                    ]),
                    "minimum_access_level": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Lowest symbol access level to document. Use 'internal' when the articles link internal symbols. Defaults to 'public'.",
                        ),
                        "enum": .array(Self.accessLevels.map { .string($0) }),
                    ]),
                    "render": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Keep the rendered .doccarchive. Defaults to false, which reports diagnostics only.",
                        ),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Where to write the .doccarchive when render is true. Defaults to .build/documentation in the package.",
                        ),
                    ]),
                    "analyze": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include note-level diagnostics. Defaults to false, which reports warnings and errors.",
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum time in seconds for each step. Defaults to 300 (5 minutes), or 900 (15 minutes) on a cold build cache.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(
        arguments: [String: Value],
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let accessLevel = arguments.getString("minimum_access_level") ?? "public"
        let render = arguments.getBool("render")
        let analyze = arguments.getBool("analyze")
        let explicitOutput = arguments.getString("output_path").map {
            PathUtility.resolvePath(from: $0)
        }
        let explicitTimeout = arguments.explicitTimeout()
        let timeout = explicitTimeout
            ?? (SwiftRunner.isColdCache(packagePath: packagePath)
                ? SwiftRunner.coldCacheTimeout
                : SwiftRunner.defaultTimeout)

        guard Self.accessLevels.contains(accessLevel) else {
            throw MCPError.invalidParams(
                "minimum_access_level must be one of: \(Self.accessLevels.joined(separator: ", ")).",
            )
        }
        let packageSwiftPath = URL(fileURLWithPath: packagePath).appendingPathComponent(
            "Package.swift",
        ).path
        guard FileManager.default.fileExists(atPath: packageSwiftPath) else {
            throw MCPError.invalidParams(
                "No Package.swift found at \(packagePath). Please provide a valid Swift package path.",
            )
        }

        do {
            let doccPath = try await Self.findDocC()
            let catalogs = try await resolveCatalogs(
                packagePath: packagePath, arguments: arguments, timeout: timeout,
            )

            if catalogs.count > 1, explicitOutput != nil, render {
                throw MCPError.invalidParams(
                    "output_path names a single archive, but \(catalogs.count) catalogs were found. Pass catalog_path to pick one.",
                )
            }

            let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "xc-mcp-docs-\(UUID().uuidString)",
            )
            try FileManager.default.createDirectory(
                at: workDirectory, withIntermediateDirectories: true,
            )
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            // One symbol-graph dump covers every target, so it runs once for all catalogs.
            var symbolGraphDirectory: String?

            if catalogs.contains(where: { $0.moduleName != nil }) {
                symbolGraphDirectory = try await dumpSymbolGraph(
                    packagePath: packagePath,
                    accessLevel: accessLevel,
                    timeout: timeout,
                    onProgress: onProgress,
                )
            }

            var sections: [String] = []
            var failed = false

            for catalog in catalogs {
                let outcome = try await build(
                    catalog: catalog,
                    doccPath: doccPath,
                    packagePath: packagePath,
                    symbolGraphDirectory: symbolGraphDirectory,
                    workDirectory: workDirectory,
                    explicitOutput: explicitOutput,
                    render: render,
                    analyze: analyze,
                    timeout: timeout,
                )
                sections.append(outcome.report)
                if outcome.failed { failed = true }
            }

            let output = sections.joined(separator: "\n\n")
            if failed { throw MCPError.internalError(output) }

            return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }

    // MARK: - Steps

    /// Result of building one catalog.
    private struct BuildOutcome {
        let report: String
        let failed: Bool
    }

    /// Locates the `docc` binary in the active toolchain.
    private static func findDocC() async throws -> String {
        let result = try await ProcessResult.run(
            "/usr/bin/xcrun", arguments: ["--find", "docc"], mergeStderr: false,
        )
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !path.isEmpty else {
            throw MCPError.internalError(
                "docc not found in the active toolchain. Select an Xcode with xcode-select.",
            )
        }
        return path
    }

    /// Finds the catalogs to build and maps each one to the target that owns it.
    private func resolveCatalogs(
        packagePath: String,
        arguments: [String: Value],
        timeout: Duration,
    ) async throws -> [DocCCatalog] {
        var catalogPaths: [String]

        if let explicit = arguments.getString("catalog_path") {
            let resolved = PathUtility.resolvePath(from: explicit)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { throw MCPError.invalidParams("No documentation catalog found at \(resolved).") }
            catalogPaths = [resolved]
        } else {
            catalogPaths = Self.findCatalogs(in: packagePath)
            guard !catalogPaths.isEmpty else {
                throw MCPError.invalidParams(
                    "No .docc catalog found under \(packagePath). Pass catalog_path to build one elsewhere.",
                )
            }
        }

        let targets = try await loadTargets(packagePath: packagePath, timeout: timeout)
        return Self.matchCatalogs(catalogPaths, toTargets: targets, packagePath: packagePath)
    }

    /// Reads the target list from the package manifest.
    private func loadTargets(
        packagePath: String,
        timeout: Duration,
    ) async throws -> [PackageTarget] {
        let result = try await swiftRunner.dumpPackage(packagePath: packagePath, timeout: timeout)
        guard result.succeeded else {
            throw MCPError.internalError(
                "Failed to read the package manifest:\n\(result.errorOutput)",
            )
        }
        let data = Data(result.stdout.utf8)
        guard let manifest = try? JSONDecoder().decode(PackageManifest.self, from: data) else {
            return []
        }
        return manifest.targets
    }

    /// Emits the symbol graph and returns the directory SwiftPM wrote it to.
    private func dumpSymbolGraph(
        packagePath: String,
        accessLevel: String,
        timeout: Duration,
        onProgress: (@Sendable (String) -> Void)?,
    ) async throws -> String {
        let result = try await swiftRunner.dumpSymbolGraph(
            packagePath: packagePath,
            minimumAccessLevel: accessLevel,
            timeout: timeout,
            onProgress: onProgress,
        )
        guard result.succeeded else {
            let parsed = ErrorExtractor.parseBuildOutput(result.output)
            let details = BuildResultFormatter.formatBuildResult(parsed)
            throw MCPError.internalError("Symbol graph generation failed:\n\(details)")
        }
        guard let directory = Self.symbolGraphDirectory(fromOutput: result.output) else {
            throw MCPError.internalError(
                "swift package dump-symbol-graph did not report an output directory:\n\(result.output)",
            )
        }
        return directory
    }

    /// Runs `docc convert` for one catalog and formats its diagnostics.
    private func build(
        catalog: DocCCatalog,
        doccPath: String,
        packagePath: String,
        symbolGraphDirectory: String?,
        workDirectory: URL,
        explicitOutput: String?,
        render: Bool,
        analyze: Bool,
        timeout: Duration,
    ) async throws -> BuildOutcome {
        let slug = catalog.displayName
        let archivePath: String =
            if render {
                explicitOutput
                    ?? URL(fileURLWithPath: packagePath)
                    .appendingPathComponent(".build/documentation/\(slug).doccarchive").path
            } else {
                workDirectory.appendingPathComponent("\(slug).doccarchive").path
            }
        let diagnosticsPath = workDirectory.appendingPathComponent("\(slug)-diagnostics.json").path
        // docc refuses to run when the parent of the output path is missing, and the default render
        // path names a `.build/documentation` directory that no build creates.
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: archivePath).deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )

        var arguments = [
            "convert", catalog.path,
            "--output-path", archivePath,
            "--diagnostics-file", diagnosticsPath,
            "--fallback-display-name", slug,
            "--fallback-bundle-identifier", "xc-mcp.\(slug)",
        ]
        if analyze { arguments.append("--analyze") }

        if let module = catalog.moduleName, let symbolGraphDirectory {
            let filtered = workDirectory.appendingPathComponent("symbolgraph-\(module)").path
            try Self.copySymbolGraphs(module: module, from: symbolGraphDirectory, to: filtered)
            arguments.append(contentsOf: ["--additional-symbol-graph-dir", filtered])
        }

        let result = try await ProcessResult.run(
            doccPath, arguments: arguments, mergeStderr: false, timeout: timeout,
        )

        var diagnostics: [DocCDiagnostic] = []

        if let data = FileManager.default.contents(atPath: diagnosticsPath),
            let parsed = try? DocCDiagnosticParser.parse(diagnosticsFile: data)
        {
            diagnostics = parsed
        } else {
            diagnostics = DocCDiagnosticParser.parseConsole(result.output)
        }

        let hasErrors = diagnostics.contains { $0.severity == "error" }
        let failed = !result.succeeded || hasErrors

        var lines = ["## \(catalog.displayName)"]
        lines.append("")
        lines.append("Catalog: \(PathUtility.relativePath(catalog.path, from: packagePath))")

        if catalog.moduleName == nil {
            lines.append(
                "No target owns this catalog, so symbol links resolve against articles only.",
            )
        }
        if render { lines.append("Archive: \(archivePath)") }
        lines.append("")
        lines.append(DocCDiagnosticFormatter.summary(diagnostics))

        let body = DocCDiagnosticFormatter.format(diagnostics, relativeTo: packagePath)

        if !body.isEmpty {
            lines.append("")
            lines.append(body)
        }
        if failed, diagnostics.isEmpty {
            lines.append("")
            lines.append("docc failed:\n\(result.errorOutput)")
        }

        return .init(report: lines.joined(separator: "\n"), failed: failed)
    }

    // MARK: - Catalog discovery

    /// A documentation catalog and the module whose symbols it documents.
    struct DocCCatalog: Sendable, Equatable {
        /// Absolute path of the `.docc` directory.
        let path: String

        /// Module name of the target that owns the catalog. Nil when no target does.
        let moduleName: String?

        /// Name used for the archive and for the DocC fallback display name.
        var displayName: String {
            moduleName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }

    /// One target from `swift package dump-package`.
    struct PackageTarget: Decodable, Sendable, Equatable {
        let name: String
        let path: String?
        let type: String
    }

    /// The subset of the package manifest the tool reads.
    private struct PackageManifest: Decodable {
        let targets: [PackageTarget]
    }

    /// Finds every `.docc` directory in the package, skipping build products and hidden
    /// directories.
    static func findCatalogs(in packagePath: String) -> [String] {
        let root = URL(fileURLWithPath: packagePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else { return [] }

        var catalogs: [String] = []

        for case let url
            as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        {
            if url.pathExtension == "docc" {
                catalogs.append(url.path)
                // A catalog holds no nested catalog, so its contents need no walk.
                enumerator.skipDescendants()
            }
        }
        return catalogs.sorted()
    }

    /// Maps each catalog to the target whose source directory contains it.
    ///
    /// - Parameters:
    ///   - catalogPaths: Absolute paths of the catalogs.
    ///   - targets: Targets read from the package manifest.
    ///   - packagePath: Package root the target paths resolve against.
    /// - Returns: One entry per catalog, in the order given.
    static func matchCatalogs(
        _ catalogPaths: [String],
        toTargets targets: [PackageTarget],
        packagePath: String,
    ) -> [DocCCatalog] {
        let root = URL(fileURLWithPath: packagePath).standardizedFileURL.path
        let directories: [(directory: String, module: String)] = targets.map { target in
            let relative = target.path ?? Self.defaultTargetPath(for: target)
            let resolved = relative.hasPrefix("/")
                ? URL(fileURLWithPath: relative).standardizedFileURL.path
                : URL(fileURLWithPath: root + "/" + relative).standardizedFileURL.path
            return (resolved, moduleName(forTarget: target.name))
        }

        return catalogPaths.map { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            // The deepest matching target wins, so a nested target beats its parent directory.
            let match = directories
                .filter { standardized.hasPrefix($0.directory + "/") }
                .max { $0.directory.count < $1.directory.count }
            return DocCCatalog(path: standardized, moduleName: match?.module)
        }
    }

    /// Returns the conventional source directory for a target that declares no `path`.
    private static func defaultTargetPath(for target: PackageTarget) -> String {
        target.type == "test" ? "Tests/\(target.name)" : "Sources/\(target.name)"
    }

    /// Converts a target name into the module name the compiler emits.
    ///
    /// SwiftPM replaces every character that a C99 identifier cannot hold with an underscore, so a
    /// target named `my-lib` compiles into the module `my_lib`.
    static func moduleName(forTarget name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
    }

    // MARK: - Symbol graphs

    /// Reads the output directory from the `swift package dump-symbol-graph` log.
    static func symbolGraphDirectory(fromOutput output: String) -> String? {
        let marker = "Files written to "

        for line in output.split(separator: "\n").reversed() {
            guard let range = line.range(of: marker) else { continue }
            let path = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !path.isEmpty { return path }
        }
        return nil
    }

    /// Selects the symbol graph files that belong to one module.
    ///
    /// A module contributes `<Module>.symbols.json` plus one `<Module>@<Other>.symbols.json` per
    /// module it extends. Every other file belongs to a different target, and DocC would document
    /// it as a second module.
    static func symbolGraphFiles(in fileNames: [String], module: String) -> [String] {
        fileNames.filter { $0 == "\(module).symbols.json" || $0.hasPrefix("\(module)@") }
    }

    /// Copies one module's symbol graph files into a directory of their own.
    private static func copySymbolGraphs(
        module: String,
        from sourceDirectory: String,
        to destinationDirectory: String,
    ) throws {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: sourceDirectory)) ?? []
        try manager.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)

        for name in symbolGraphFiles(in: names, module: module) {
            let source = sourceDirectory + "/" + name
            let destination = destinationDirectory + "/" + name
            try? manager.removeItem(atPath: destination)
            try manager.copyItem(atPath: source, toPath: destination)
        }
    }
}
