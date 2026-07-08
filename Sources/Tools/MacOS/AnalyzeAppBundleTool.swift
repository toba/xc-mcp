import MCP
import XCMCPCore
import Foundation

/// Read-only inspection of a *built* macOS `.app` bundle (or the `.app` inside an `.xcarchive`):
/// total size, main-executable Mach-O segment breakdown, which in-project frameworks are linked
/// (`otool -L` `@rpath`) vs embedded (`Contents/Frameworks`), `LC_RPATH` entries, mergeable-library
/// merge metadata (`_relinkableLibraryClasses`), and whether the bundle is self-contained.
///
/// The key distinction this makes obvious: a loose build product is typically *not* self-contained
/// — many frameworks resolve via `DYLD_FRAMEWORK_PATH` at dev-run time and only an archive embeds
/// everything. Rather than an agent rediscovering that via dyld crash logs, `check_launchable`
/// cross-references linked `@rpath` deps against embedded frameworks + rpaths and reports the gap.
public struct AnalyzeAppBundleTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "analyze_app_bundle",
            description:
                "Inspect a BUILT macOS .app bundle (or the .app inside an .xcarchive): total size, "
                + "main-executable Mach-O segment sizes, linked (@rpath) vs embedded frameworks, "
                + "LC_RPATH entries, mergeable-library merge metadata (_relinkableLibraryClasses), "
                + "and whether the bundle is self-contained/launchable standalone. Read-only. "
                + "Complements find_link_flag (which only reads the project file). If app_path is "
                + "omitted, resolves from session project/scheme/configuration like get_mac_app_path.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a .app bundle OR a .xcarchive (the .app inside is located "
                                + "automatically). If omitted, resolved from build settings.",
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Used to resolve the built app from build "
                                + "settings when app_path is omitted.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Used to resolve the built app from build "
                                + "settings when app_path is omitted.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to resolve the app path for. Uses session default if not set.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Release for size "
                                + "analysis (fall back to session default, then Release).",
                        ),
                    ]),
                    "check_launchable": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Cross-reference linked @rpath deps against embedded frameworks + rpaths "
                                + "and report any that would not resolve standalone. Default true.",
                        ),
                    ]),
                    "include_frameworks": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Report per-embedded-framework binary sizes. Default true.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let checkLaunchable = arguments.getBool("check_launchable", default: true)
        let includeFrameworks = arguments.getBool("include_frameworks", default: true)

        do {
            let appPath = try await resolveAppPath(arguments: arguments)
            let report = try await analyze(
                appPath: appPath,
                checkLaunchable: checkLaunchable,
                includeFrameworks: includeFrameworks,
            )
            return CallTool.Result(content: [.text(text: report, annotations: nil, _meta: nil)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw try error.asMCPError()
        }
    }

    // MARK: - App path resolution

    private func resolveAppPath(arguments: [String: Value]) async throws -> String {
        if let provided = arguments.getString("app_path") {
            return try locateApp(inputPath: provided)
        }

        // Resolve from build settings (mirror get_mac_app_path).
        let sessionProjectPath = await sessionManager.projectPath
        let sessionWorkspacePath = await sessionManager.workspacePath
        let projectPath = arguments.getString("project_path") ?? sessionProjectPath
        let workspacePath = arguments.getString("workspace_path") ?? sessionWorkspacePath

        let sessionScheme = await sessionManager.scheme
        guard let scheme = arguments.getString("scheme") ?? sessionScheme else {
            throw MCPError.invalidParams(
                "scheme is required when app_path is omitted. Set it with set_session_defaults or "
                    + "pass it directly.",
            )
        }

        let sessionConfiguration = await sessionManager.configuration
        let configuration = arguments.getString("configuration") ?? sessionConfiguration
            ?? "Release"

        if projectPath == nil, workspacePath == nil {
            throw MCPError.invalidParams(
                "Either app_path, project_path, or workspace_path is required.",
            )
        }

        let buildSettings = try await xcodebuildRunner.showBuildSettings(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            configuration: configuration,
            destination: XcodebuildRunner.macOSDestination,
        )

        guard let appPath = BuildSettingExtractor.extractAppPath(from: buildSettings.stdout) else {
            throw MCPError.internalError(
                "Could not determine app path from build settings. Build the project first with "
                    + "build_macos (configuration: \(configuration)).",
            )
        }

        guard FileManager.default.fileExists(atPath: appPath) else {
            throw MCPError.internalError(
                "App not found at expected path: \(appPath). Build the project first with build_macos "
                    + "(configuration: \(configuration)).",
            )
        }

        return appPath
    }

    /// Accepts a `.app` or `.xcarchive` path and returns the `.app` to analyze.
    private func locateApp(inputPath: String) throws -> String {
        let fm = FileManager.default
        let path = (inputPath as NSString).expandingTildeInPath

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPError.invalidParams(
                "Path does not exist or is not a bundle directory: \(path)")
        }

        if path.hasSuffix(".app") { return path }

        if path.hasSuffix(".xcarchive") {
            let productsApps = path + "/Products/Applications"
            if let entries = try? fm.contentsOfDirectory(atPath: productsApps),
               let app = entries.first(where: { $0.hasSuffix(".app") }) {
                return productsApps + "/" + app
            }
            throw MCPError.invalidParams("No .app found under \(productsApps) in the archive.")
        }

        throw MCPError.invalidParams(
            "app_path must point to a .app bundle or a .xcarchive: \(path)",
        )
    }

    // MARK: - Analysis

    private func analyze(
        appPath: String,
        checkLaunchable: Bool,
        includeFrameworks: Bool,
    ) async throws -> String {
        let fm = FileManager.default
        let appName = (appPath as NSString).lastPathComponent

        // Main executable from Info.plist CFBundleExecutable.
        guard let executableName = mainExecutableName(appPath: appPath) else {
            throw MCPError.internalError(
                "Could not read CFBundleExecutable from \(appPath)/Contents/Info.plist.",
            )
        }
        let mainExecutable = appPath + "/Contents/MacOS/" + executableName
        guard fm.fileExists(atPath: mainExecutable) else {
            throw MCPError.internalError("Main executable not found: \(mainExecutable)")
        }

        // Embedded frameworks (Contents/Frameworks, including nested .framework/.dylib).
        let embedded = embeddedFrameworks(appPath: appPath)

        // Sizes.
        let totalSize = directorySize(appPath)
        let mainExeSize = fileSize(mainExecutable)
        let embeddedBinariesSize = embedded.reduce(0) { $0 + $1.binarySize }
        let resourceSize = max(0, totalSize - mainExeSize - embeddedBinariesSize)

        // cctools `otool`/`size` mis-tokenize paths with spaces even via argv; run all Mach-O tools
        // against spaceless symlinks so a path like "My App (debug)" — or an executable whose own
        // leaf name has a space — needs no caller-side hack. Only subprocess arguments use the
        // mapped paths; logical resolution below still uses the real bundle paths.
        let executableDir = appPath + "/Contents/MacOS"
        let (safeMap, cleanup) = spaceSafeBinaries(
            [mainExecutable] + embedded.compactMap(\.binaryPath))
        defer { cleanup() }
        let safePath: @Sendable (String) -> String = { real in safeMap[real] ?? real }
        let safeBinary = safePath(mainExecutable)

        // Mach-O inspection of the main executable (run tools concurrently).
        async let segmentsTask = machOSegments(safeBinary)
        async let linkedTask = linkedLibraries(safeBinary)
        async let rpathsTask = rpaths(safeBinary)
        async let mergeTask = relinkableClassCount(safeBinary)
        async let archsTask = architectures(safeBinary)

        let segments = await segmentsTask
        let linked = await linkedTask
        let rpaths = await rpathsTask
        let mergeCount = await mergeTask
        let archs = await archsTask

        // Build report.
        var out = ""
        out += "# Bundle analysis: \(appName)\n"
        out += "Path: \(appPath)\n\n"

        out += "## Bundle size\n"
        out += "- Total: \(humanBytes(totalSize)) (\(totalSize) bytes)\n"
        out += "- Main executable: \(humanBytes(mainExeSize))\n"
        out += "- Embedded framework binaries: \(humanBytes(embeddedBinariesSize)) "
            + "(\(embedded.count) framework\(embedded.count == 1 ? "" : "s"))\n"
        out += "- Resources & other: \(humanBytes(resourceSize))\n\n"

        out += "## Main executable\n"
        out += "- Path: Contents/MacOS/\(executableName)\n"
        out += "- Architectures: \(archs.isEmpty ? "unknown" : archs.joined(separator: ", "))\n"

        if segments.isEmpty {
            out += "- Segments: (could not parse `size -m`)\n"
        } else {
            out += "- Mach-O segments (excluding __PAGEZERO):\n"
            for seg in segments { out += "  - \(seg.name): \(humanBytes(seg.size))\n" }
        }
        out += "\n"

        out += "## Merge metadata (mergeable libraries)\n"

        if mergeCount > 0 {
            out += "- Main executable carries `_relinkableLibraryClasses`: \(mergeCount) symbol"
                + "\(mergeCount == 1 ? "" : "s") (mergeable-library merge marker present)\n"
        } else {
            out += "- No `_relinkableLibraryClasses` symbols in the main executable "
                + "(no merge metadata detected)\n"
        }
        out += "\n"

        out += "## LC_RPATH entries (\(rpaths.count))\n"
        if rpaths.isEmpty { out += "- (none)\n" } else { for rp in rpaths { out += "- \(rp)\n" } }
        out += "\n"

        let inProjectLinked = linked.filter(\.isRelative)
        out += "## Linked in-project frameworks (\(inProjectLinked.count))\n"
        out += "Filtered from `otool -L` to @rpath/@loader_path/@executable_path deps.\n"

        if inProjectLinked.isEmpty {
            out += "- (none)\n"
        } else {
            for dep in inProjectLinked { out += "- \(dep.path)\n" }
        }
        out += "\n"

        if includeFrameworks {
            out += "## Embedded frameworks (\(embedded.count))\n"

            if embedded.isEmpty {
                out += "- (none)\n"
            } else {
                for fw in embedded.sorted(by: { $0.binarySize > $1.binarySize }) {
                    out += "- \(fw.name): \(humanBytes(fw.binarySize))\n"
                }
            }
            out += "\n"
        }

        if checkLaunchable {
            // Walk the full closure: the main executable plus every embedded framework binary. An
            // app-binary-only scan misses transitive framework→framework gaps (e.g. an embedded
            // framework linking a package-product framework that itself is not embedded).
            let mainImage = MachOInspector.MachOImage(
                name: "\(executableName) (main executable)",
                loaderDir: executableDir,
                rpaths: rpaths,
                relativeDeps: inProjectLinked,
            )
            let frameworkImages = await frameworkImages(embedded: embedded, safePath: safePath)
            out += launchabilityReport(
                images: [mainImage] + frameworkImages,
                executableRpaths: rpaths,
                appPath: appPath,
                executableDir: executableDir,
            )
        }

        return out
    }

    /// Runs `otool -L`/`otool -l` against each embedded framework binary (concurrently, via the
    /// space-safe path) and reduces each to a `MachOImage` for closure resolution. Frameworks whose
    /// binary could not be located are skipped. Sorted by name for deterministic output.
    private func frameworkImages(
        embedded: [EmbeddedFramework],
        safePath: @Sendable (String) -> String,
    ) async -> [MachOInspector.MachOImage] {
        let images = await withTaskGroup(of: MachOInspector.MachOImage?.self) { group in
            for fw in embedded {
                guard let binary = fw.binaryPath else { continue }
                let name = fw.name
                let loaderDir = (binary as NSString).deletingLastPathComponent
                let safeBinary = safePath(binary)
                group.addTask(name: "analyze_app_bundle inspect \(name)") {
                    async let linkedTask = linkedLibraries(safeBinary)
                    async let rpathsTask = rpaths(safeBinary)
                    // A framework/dylib's `otool -L` lists its own install name (LC_ID_DYLIB) as
                    // the first entry; drop it so a framework isn't reported as depending on
                    // itself.
                    let deps = await linkedTask.dropFirst().filter(\.isRelative)
                    return await MachOInspector.MachOImage(
                        name: name,
                        loaderDir: loaderDir,
                        rpaths: rpathsTask,
                        relativeDeps: deps,
                    )
                }
            }
            var result = [MachOInspector.MachOImage]()
            for await image in group { if let image { result.append(image) } }
            return result
        }
        return images.sorted { $0.name < $1.name }
    }

    // MARK: - Launchability

    /// Walks the full dependency closure (main executable + every embedded framework) and resolves
    /// each `@rpath`/`@loader_path`/`@executable_path` dependency dyld-style against the bundle.
    /// Anything that lands on no file inside the bundle — including transitive framework→framework
    /// deps an app-binary scan misses — is flagged as the launchability gap, annotated with which
    /// images reference it.
    private func launchabilityReport(
        images: [MachOInspector.MachOImage],
        executableRpaths: [String],
        appPath: String,
        executableDir: String,
    ) -> String {
        let fm = FileManager.default
        let totalDeps = images.reduce(0) { $0 + $1.relativeDeps.count }
        let missing = MachOInspector.unresolvedClosure(
            images: images,
            executableDir: executableDir,
            executableRpaths: executableRpaths,
            appPath: appPath,
            fileExists: { fm.fileExists(atPath: $0) },
        )

        var out = "## Embedding completeness / launchability\n"
        out += "Full closure scanned: \(images.count) Mach-O image"
            + "\(images.count == 1 ? "" : "s") (main executable + embedded frameworks), "
            + "\(totalDeps) @rpath dependenc\(totalDeps == 1 ? "y" : "ies").\n"

        if totalDeps == 0 {
            out += "- No @rpath dependencies to resolve.\n"
            return out
        }
        if missing.isEmpty {
            out +=
                "- ✅ Self-contained: every @rpath dependency across the whole closure resolves to a "
                + "file inside the bundle (via Contents/Frameworks, Contents/MacOS, or an "
                + "@executable_path rpath). This bundle should launch standalone.\n"
        } else {
            out += "- ⚠️ NOT self-contained: \(missing.count) @rpath dependenc"
                + "\(missing.count == 1 ? "y does" : "ies do") not resolve to any file inside the "
                + "bundle. A loose build product resolves these via an absolute DerivedData rpath "
                + "(DYLD_FRAMEWORK_PATH) at dev-run time; a standalone copy would fail to launch "
                + "(dyld: Library not loaded). Only an archive (export_archive) embeds everything.\n"
            out += "- Missing (linked-but-not-embedded), with referencing image(s):\n"

            for m in missing {
                out += "  - \(m.dep)\n"
                out += "    referenced by: \(m.referencedBy.joined(separator: ", "))\n"
            }
        }
        return out
    }

    // MARK: - Info.plist

    private func mainExecutableName(appPath: String) -> String? {
        let plistPath = appPath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil,
            ) as? [String: Any] else { return nil }
        return plist["CFBundleExecutable"] as? String
    }

    // MARK: - Embedded frameworks

    private struct EmbeddedFramework: Sendable {
        let name: String
        let binarySize: Int
        /// Absolute path to the framework/dylib Mach-O binary, or nil if it could not be located.
        let binaryPath: String?
    }

    private func embeddedFrameworks(appPath: String) -> [EmbeddedFramework] {
        let fm = FileManager.default
        let frameworksDir = appPath + "/Contents/Frameworks"
        guard let enumerator = fm.enumerator(atPath: frameworksDir) else { return [] }

        var results = [EmbeddedFramework]()

        for case let rel as String in enumerator {
            let full = frameworksDir + "/" + rel

            if rel.hasSuffix(".framework") {
                // Framework binary is Versions/A/<name> or <name> at the framework root.
                let base = (rel as NSString).lastPathComponent
                let name = (base as NSString).deletingPathExtension
                let binaryPath = frameworkBinary(frameworkPath: full, name: name)
                results.append(.init(
                    name: base, binarySize: binaryPath.map(fileSize) ?? 0, binaryPath: binaryPath,
                ))
                enumerator.skipDescendants()
            } else if rel.hasSuffix(".dylib") {
                let base = (rel as NSString).lastPathComponent
                results.append(.init(name: base, binarySize: fileSize(full), binaryPath: full))
            }
        }
        return results
    }

    private func frameworkBinary(frameworkPath: String, name: String) -> String? {
        let fm = FileManager.default
        let candidates = [
            frameworkPath + "/Versions/A/" + name,
            frameworkPath + "/Versions/Current/" + name,
            frameworkPath + "/" + name,
        ]
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    // MARK: - Mach-O tooling (otool / size / nm / lipo)
    //
    // Each runner shells out and hands the raw output to a pure `MachOInspector` parser (unit-tested
    // separately). On any tool failure they return empty so a single missing tool degrades one
    // section rather than the whole report.

    /// `size -m` segments, excluding the __PAGEZERO artifact.
    private func machOSegments(_ binary: String) async -> [MachOInspector.Segment] {
        guard let result = try? await ProcessResult.xcrun("size", arguments: ["-m", binary]),
              result.succeeded else { return [] }
        return MachOInspector.parseSegments(result.stdout)
    }

    private func linkedLibraries(_ binary: String) async -> [MachOInspector.LinkedLibrary] {
        guard let result = try? await ProcessResult.xcrun("otool", arguments: ["-L", binary]),
              result.succeeded else { return [] }
        return MachOInspector.parseLinkedLibraries(result.stdout)
    }

    private func rpaths(_ binary: String) async -> [String] {
        guard let result = try? await ProcessResult.xcrun("otool", arguments: ["-l", binary]),
              result.succeeded else { return [] }
        return MachOInspector.parseRpaths(result.stdout)
    }

    private func relinkableClassCount(_ binary: String) async -> Int {
        guard let result = try? await ProcessResult.xcrun("nm", arguments: [binary]),
              result.succeeded || !result.stdout.isEmpty else { return 0 }
        return MachOInspector.countRelinkableClasses(result.stdout)
    }

    private func architectures(_ binary: String) async -> [String] {
        guard let result = try? await ProcessResult.xcrun("lipo", arguments: ["-archs", binary]),
              result.succeeded else { return [] }
        return MachOInspector.parseArchitectures(result.stdout)
    }

    // MARK: - Space-safe path workaround

    /// cctools `otool`/`size` re-split their file argument on whitespace internally, so a path
    /// containing a space (e.g. `My App (debug)`) fails to open even when passed as a single argv
    /// element. This bites both a bundle path with a space *and* an executable/framework whose own
    /// leaf name has one (e.g. `ThesisApp (debug)`). These Mach-O tools each read a single file and
    /// don't traverse the bundle, so the fix is to symlink every binary we inspect into a fresh
    /// temp dir under a spaceless name and target the symlink. Returns a real→spaceless map (only
    /// for paths with a space) plus a cleanup closure; paths without a space are absent and used
    /// as-is.
    ///
    /// Only subprocess *arguments* use the mapped paths; logical resolution (rpath prefix checks,
    /// `fileExists`) still runs against the real bundle paths.
    private func spaceSafeBinaries(
        _ binaries: [String],
    ) -> (map: [String: String], cleanup: @Sendable () -> Void) {
        let needing = binaries.filter { $0.contains(" ") }
        guard !needing.isEmpty else { return ([:], {}) }
        let fm = FileManager.default
        let tmpDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("xc-mcp-aab-" + UUID().uuidString)
        guard (try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)) != nil
        else { return ([:], {}) }
        var map = [String: String]()

        for (index, real) in needing.enumerated() {
            let link = (tmpDir as NSString).appendingPathComponent("bin-\(index)")
            if (try? fm.createSymbolicLink(atPath: link, withDestinationPath: real)) != nil {
                map[real] = link
            }
        }
        return (map, { try? FileManager.default.removeItem(atPath: tmpDir) })
    }

    // MARK: - Filesystem sizing

    private func fileSize(_ path: String) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? Int else { return 0 }
        return size
    }

    private func directorySize(_ path: String) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [
                .totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey,
            ],
            options: [],
        ) else { return fileSize(path) }

        var total = 0

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += values.fileSize ?? 0
        }
        return total
    }

    private func humanBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0

        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0
            ? "\(bytes) B"
            : String(format: "%.1f %@", value, units[unit])
    }
}
