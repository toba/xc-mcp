import MCP
import XCMCPCore
import Foundation

public struct SwiftSymbolsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        .init(
            name: "swift_symbols",
            description:
                "Extract and query the public API of a Swift module (system framework or SPM dependency). "
                + "Wraps swift-symbolgraph-extract to show declarations, types, and availability. "
                + "Use to discover APIs without reading source (e.g. \"does SwiftUI export ScrollPosition?\").",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "module": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Module name to inspect (e.g. 'Testing', 'SwiftUI', 'Foundation').",
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
                            "Include doc comments in output. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([.string("module")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let module = try arguments.getRequiredString("module")
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

        let graph = try await SymbolGraphCache.shared.graph(
            module: module,
            platform: platform,
            sdkPath: sdkPath,
            triple: platformInfo.triple,
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
            module: module, platform: platform, symbols: symbols, showDoc: showDoc,
        )

        return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
    }
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
    let triple: String
}

private func resolvePlatform(_ platform: String) throws -> PlatformInfo {
    switch platform.lowercased() {
        case "macos": return PlatformInfo(sdk: "macosx", triple: "arm64-apple-macos15.0")
        case "ios": return PlatformInfo(sdk: "iphoneos", triple: "arm64-apple-ios18.0")
        case "watchos": return PlatformInfo(sdk: "watchos", triple: "arm64-apple-watchos11.0")
        case "tvos": return PlatformInfo(sdk: "appletvos", triple: "arm64-apple-tvos18.0")
        case "visionos": return PlatformInfo(sdk: "xros", triple: "arm64-apple-xros2.0")
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
) -> String {
    var lines: [String] = []
    lines.append("Module: \(module) (\(platform), \(symbols.count) symbols)")
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
/// output is deterministic for a given `(module, platform, sdkPath, triple)` . Caching the decoded
/// graph means a single MCP session that queries the same module multiple times — and tests that
/// run in parallel against the same module — pay the extraction cost once.
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
    ) async throws -> SymbolGraph {
        let key = "\(module)|\(platform)|\(sdkPath)|\(triple)"
        if let cached = cached[key] { return cached }
        if let inflight = inflight[key] { return try await inflight.value }
        let task = Task {
            try await Self.extract(
                module: module, platform: platform, sdkPath: sdkPath, triple: triple,
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

        let extractResult = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: .init(extractArgs),
            timeout: .seconds(60),
        )
        guard extractResult.succeeded else {
            throw MCPError.internalError(
                "swift-symbolgraph-extract failed for module '\(module)': \(extractResult.errorOutput)",
            )
        }

        let symbolGraphPath = tmpDir.appendingPathComponent("\(module).symbols.json")
        let data = try Data(contentsOf: symbolGraphPath)
        return try JSONDecoder().decode(SymbolGraph.self, from: data)
    }
}

// MARK: - Symbol graph models

private struct SymbolGraph: Decodable, Sendable {
    let symbols: [Symbol]

    private enum CodingKeys: String, CodingKey {
        case symbols
    }
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
