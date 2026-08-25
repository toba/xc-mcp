import MCP
import XCMCPCore
import Foundation

public struct SwiftSymbolsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        .init(
            name: "swift_symbols",
            description: "Extract and query the public API of a Swift module. "
                + "Wraps swift-symbolgraph-extract to show declarations, types, and availability. "
                + "Use to discover APIs without reading source (e.g. \"does SwiftUI export ScrollPosition?\"). "
                + "A module in the SDK or the platform Developer frameworks needs no other argument (e.g. SwiftUI, Testing). "
                + "Pass project_path to reach a module that a Swift package built, which covers the package targets "
                + "and the SPM dependencies (e.g. OrderedCollections). That package must have built already.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "module": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Module name to inspect (e.g. 'Testing', 'SwiftUI', 'Foundation').",
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a Swift package root (the directory holding Package.swift). Adds that package's built modules to the search, so a package target or an SPM dependency resolves. The SDK is still searched.",
                        ),
                    ]),
                    "query": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter symbols by name (case-insensitive substring match).",
                        ),
                    ]),
                    "kind": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter by symbol kind: struct, func, enum, protocol, class, typealias, macro, property, method, init, case.",
                        ),
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Target platform: macos (default), ios, watchos, tvos, visionos.",
                        ),
                    ]),
                    "show_doc": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include doc comments in output. Defaults to false."),
                    ]),
                ]),
                "required": .array([.string("module")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let module = try arguments.getRequiredString("module")
        let projectPath = arguments.getNonEmptyString("project_path")
        let query = arguments.getString("query")
        let kindFilter = arguments.getString("kind")
        let platform = arguments.getString("platform") ?? "macos"
        let showDoc = arguments.getBool("show_doc")

        let platformInfo = try resolvePlatform(platform)

        // Resolve SDK path
        let sdkResult = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["--show-sdk-path", "--sdk", platformInfo.sdk],
            timeout: .seconds(10),
        )
        guard sdkResult.succeeded else {
            throw MCPError
                .internalError(
                    "Failed to resolve SDK path for \(platform): \(sdkResult.errorOutput)",
                )
        }
        let sdkPath = sdkResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let triple = await platformInfo.triple()

        let searchPaths =
            projectPath
            .map { PackageModuleLocator.searchPaths(packagePath: $0) } ?? []

        let graph = try await SymbolGraphCache.shared.graph(
            module: module,
            platform: platform,
            sdkPath: sdkPath,
            triple: triple,
            searchPaths: searchPaths,
            failureHint: failureHint(projectPath: projectPath, searchPaths: searchPaths),
        )

        // Filter symbols
        var symbols = graph.symbols

        // Filter by kind
        if let kindFilter {
            let mappedKind = mapKind(kindFilter)
            symbols = symbols.filter { $0.kind.identifier == mappedKind }
        }

        // Filter by query
        if let query {
            let lowered = query.lowercased()
            symbols = symbols.filter { symbol in
                symbol.names.title.lowercased().contains(lowered)
                    || symbol.pathComponents.contains { $0.lowercased().contains(lowered) }
            }
        }

        // Sort by name
        symbols.sort { $0.names.title < $1.names.title }

        // Format output
        let output = formatOutput(
            module: module,
            platform: platform,
            symbols: symbols,
            showDoc: showDoc,
            searchPaths: searchPaths,
        )

        return CallTool.Result.text(output)
    }
}

// MARK: - Failure text

/// The next action offered when the caller named no package.
private let packageSearchAction =
    "A module a Swift package builds needs that package. Pass project_path, the directory that holds Package.swift."

/// The sentence appended to an extraction failure, telling the caller what the package contributed.
///
/// A package with no build output is the common cause of a module the tool cannot find, and the
/// compiler's own message never mentions it.
private func failureHint(projectPath: String?, searchPaths: [String]) -> String? {
    guard let projectPath else { return nil }
    return searchPaths.isEmpty
        ? "No built modules were found under \(projectPath)/.build, so only the SDK was searched. Build the package first."
        : "Searched the package modules in: \(searchPaths.joined(separator: ", ")). "
            + "A module that imports a C target can still fail to load, because the module map of that target is not on the search path. "
            + "Confirm the name against the targets in Package.swift, then build the package again."
}

/// The reply to an extraction the compiler refused.
///
/// The compiler answers a module it cannot load with every visible module, over 400 names on macOS.
/// The reply keeps the names closest to the requested one and ends with the next action. The raw
/// output stands when the failure has another cause, because it then carries the reason.
private func loadFailureMessage(
    module: String,
    platform: String,
    errorOutput: String,
    searchPaths: [String],
    failureHint: String?,
) -> String {
    let candidates = VisibleModuleList.closest(to: module, in: errorOutput)
    guard !candidates.isEmpty else {
        var message = "swift-symbolgraph-extract failed for module '\(module)': \(errorOutput)"
        if let failureHint { message += " \(failureHint)" }
        return message
    }

    let summary = searchPaths.isEmpty
        ? "Module '\(module)' is not in the \(platform) SDK."
        : "Module '\(module)' is in neither the \(platform) SDK nor the built package modules."
    return [
        summary,
        "Closest visible modules: \(candidates.joined(separator: ", "))",
        failureHint ?? packageSearchAction,
    ].joined(separator: "\n")
}

// MARK: - Developer framework path

/// Resolves the Developer/Library/Frameworks path for the given platform. Modules like `Testing`
/// ship here rather than in the SDK itself.
private func resolveDeveloperFrameworkPath(sdkPath: String, platform _: String) -> String? {
    // SDK path is like .../Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.5.sdk We need
    // .../Platforms/MacOSX.platform/Developer/Library/Frameworks
    let sdkURL = URL(fileURLWithPath: sdkPath)
    // Go up from SDKs/<version>.sdk to Developer/
    let developerDir = sdkURL
        .deletingLastPathComponent()  // SDKs/
        .deletingLastPathComponent()  // Developer/
    let frameworksDir = developerDir
        .appendingPathComponent("Library")
        .appendingPathComponent("Frameworks")

    return FileManager.default.fileExists(atPath: frameworksDir.path)
        ? frameworksDir.path
        : nil
}

// MARK: - Platform resolution

private struct PlatformInfo {
    let sdk: String
    let osName: String
    /// The OS version used when the SDK version cannot be read.
    let fallbackVersion: String

    /// The target triple, carrying the installed SDK version.
    ///
    /// The version has to be at least the deployment target of the module under inspection, or the
    /// compiler refuses to load it. A package that targets the current OS is the common case, so an
    /// older pinned version would make every module of that package unreadable.
    func triple() async -> String {
        let sdkVersion = await Self.installedSDKVersion(sdk: sdk)
        return "arm64-apple-\(osName)\(sdkVersion ?? fallbackVersion)"
    }

    private static func installedSDKVersion(sdk: String) async -> String? {
        let result = try? await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["--show-sdk-version", "--sdk", sdk],
            timeout: .seconds(10),
        )
        guard let result, result.succeeded else { return nil }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }
}

private func resolvePlatform(_ platform: String) throws(MCPError) -> PlatformInfo {
    switch platform.lowercased() {
        case "macos": return PlatformInfo(sdk: "macosx", osName: "macos", fallbackVersion: "15.0")
        case "ios": return PlatformInfo(sdk: "iphoneos", osName: "ios", fallbackVersion: "18.0")
        case "watchos":
            return PlatformInfo(sdk: "watchos", osName: "watchos", fallbackVersion: "11.0")
        case "tvos": return PlatformInfo(sdk: "appletvos", osName: "tvos", fallbackVersion: "18.0")
        case "visionos": return PlatformInfo(sdk: "xros", osName: "xros", fallbackVersion: "2.0")
        default:
            throw MCPError.invalidParams(
                "Unknown platform '\(platform)'. Use: macos, ios, watchos, tvos, visionos.",
            )
    }
}

// MARK: - Kind mapping

private func mapKind(_ userKind: String) -> String {
    switch userKind.lowercased() {
        case "struct": "swift.struct"
        case "class": "swift.class"
        case "enum": "swift.enum"
        case "protocol": "swift.protocol"
        case "func", "function": "swift.func"
        case "method": "swift.method"
        case "property": "swift.property"
        case "typealias": "swift.typealias"
        case "macro": "swift.macro"
        case "init": "swift.init"
        case "case": "swift.enum.case"
        default: "swift.\(userKind.lowercased())"
    }
}

// MARK: - Output formatting

private func formatOutput(
    module: String,
    platform: String,
    symbols: [Symbol],
    showDoc: Bool,
    searchPaths: [String],
) -> String {
    var lines: [String] = []
    // header, blank, then a title and a trailing blank per symbol, plus optional detail lines
    lines.reserveCapacity(symbols.count * 3 + 3)
    lines.append("Module: \(module) (\(platform), \(symbols.count) symbols)")
    // the caller needs to know a build directory joined the search, not the SDK alone
    if !searchPaths.isEmpty {
        lines.append("Package module search: \(searchPaths.joined(separator: ", "))")
    }
    lines.append("")

    for symbol in symbols {
        let kindLabel = symbol.kind.identifier
            .replacingOccurrences(of: "swift.", with: "")
        lines.append("\(kindLabel) \(symbol.names.title)")

        // Declaration
        if let fragments = symbol.declarationFragments {
            let decl = fragments.map(\.spelling).joined()
            if !decl.isEmpty { lines.append("  declaration: \(decl)") }
        }

        // Availability
        if let availability = symbol.availability, !availability.isEmpty {
            let parts = availability.compactMap { avail -> String? in
                guard let domain = avail.domain else { return nil }
                if let intro = avail.introduced { return "\(domain) \(intro.description)" }
                return avail.isUnconditionallyDeprecated == true ? "\(domain) (deprecated)" : nil
            }
            if !parts.isEmpty { lines.append("  available: \(parts.joined(separator: ", "))") }
        }

        // Doc comment
        if showDoc, let doc = symbol.docComment {
            let text = doc.lines.map(\.text).joined(separator: "\n")
            if !text.isEmpty { lines.append("  doc: \(text)") }
        }

        lines.append("")
    }

    if symbols.isEmpty { lines.append("No symbols found.") }

    return lines.joined(separator: "\n")
}

// MARK: - Cache

/// Process-wide cache of decoded symbol graphs.
///
/// `swift-symbolgraph-extract` is expensive (10s–60s+ depending on module/SDK warmth) and the
/// output is deterministic for a given `(module, platform, sdkPath, triple, searchPaths)` . Caching
/// the decoded graph means a single MCP session that queries the same module multiple times — and
/// tests that run in parallel against the same module — pay the extraction cost once.
///
/// No eviction is intentional. The key cardinality is bounded by realistic input: one toolchain
/// pins `sdkPath` , ~5 platforms each pin a `triple` , and an MCP session typically queries a
/// handful of distinct modules. Total live entries stay in the low tens, and each `SymbolGraph` is
/// a parsed JSON tree (small relative to a single `swift build` ).
private actor SymbolGraphCache {
    static let shared = SymbolGraphCache()

    private var inflight: [String: Task<SymbolGraph, Error>] = [:]
    private var cached: [String: SymbolGraph] = [:]

    func graph(
        module: String,
        platform: String,
        sdkPath: String,
        triple: String,
        searchPaths: [String] = [],
        failureHint: String? = nil,
    ) async throws -> SymbolGraph {
        let key = "\(module)|\(platform)|\(sdkPath)|\(triple)|\(searchPaths.joined(separator: ":"))"
        if let cached = cached[key] { return cached }
        if let inflight = inflight[key] { return try await inflight.value }
        let task = Task(name: "symbol-graph-extract:\(module)") {
            try await Self.extract(
                module: module,
                platform: platform,
                sdkPath: sdkPath,
                triple: triple,
                searchPaths: searchPaths,
                failureHint: failureHint,
            )
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        let graph = try await task.value
        cached[key] = graph
        return graph
    }

    private static func extract(
        module: String,
        platform: String,
        sdkPath: String,
        triple: String,
        searchPaths: [String],
        failureHint: String?,
    ) async throws -> SymbolGraph {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-symbols-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let developerFrameworkPath = resolveDeveloperFrameworkPath(
            sdkPath: sdkPath, platform: platform,
        )

        var extractArgs = [
            "swift-symbolgraph-extract",
            "-module-name", module,
            "-target", triple,
            "-sdk", sdkPath,
            "-output-dir", tmpDir.path,
            "-minimum-access-level", "public",
        ]
        if let developerFrameworkPath { extractArgs += ["-F", developerFrameworkPath] }
        for searchPath in searchPaths { extractArgs += ["-I", searchPath] }

        let extractResult = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: .init(extractArgs),
            timeout: .seconds(180),
        )
        guard extractResult.succeeded else {
            throw MCPError.internalError(loadFailureMessage(
                module: module, platform: platform, errorOutput: extractResult.errorOutput,
                searchPaths: searchPaths, failureHint: failureHint,
            ))
        }

        let symbolGraphPath = tmpDir.appendingPathComponent("\(module).symbols.json")
        let data = try Data(contentsOf: symbolGraphPath)
        return try JSONDecoder().decode(SymbolGraph.self, from: data)
    }
}

// MARK: - Symbol graph models

private struct SymbolGraph: Decodable, Sendable {
    let symbols: [Symbol]

    private enum CodingKeys: String, CodingKey { case symbols }
}

private struct Symbol: Decodable {
    let kind: SymbolKind
    let names: SymbolNames
    let pathComponents: [String]
    let declarationFragments: [Fragment]?
    let availability: [Availability]?
    let docComment: DocComment?
    let accessLevel: String?
}

private struct SymbolKind: Decodable {
    let identifier: String
    let displayName: String
}

private struct SymbolNames: Decodable {
    let title: String
}

private struct Fragment: Decodable {
    let kind: String
    let spelling: String
}

private struct Availability: Decodable {
    let domain: String?
    let introduced: SemanticVersion?
    let deprecated: SemanticVersion?
    let isUnconditionallyDeprecated: Bool?
}

private struct SemanticVersion: Decodable {
    let major: Int
    let minor: Int?
    let patch: Int?

    var description: String {
        guard let minor else { return "\(major)" }
        if let patch, patch > 0 { return "\(major).\(minor).\(patch)" }
        return "\(major).\(minor)"
    }
}

private struct DocComment: Decodable {
    let lines: [DocLine]
}

private struct DocLine: Decodable {
    let text: String
}
