import MCP
import CryptoKit
import XCMCPCore
import Foundation

public struct DetectUnusedCodeTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "detect_unused_code",
            description:
            "Detect unused code in a Swift package or Xcode project using Periphery. Returns a compact summary by default; use format: \"detail\" to see per-declaration output. Automatically maintains a checklist for iterative cleanup — use mark to track progress. Supports cached results via result_file for instant drill-down without re-scanning. Requires the 'periphery' CLI (brew install periphery).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory. Uses session default if not specified. For SPM projects, this is sufficient — no project or schemes needed.",
                        ),
                    ]),
                    "project": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to .xcodeproj or .xcworkspace. Required for Xcode projects, not needed for SPM packages.",
                        ),
                    ]),
                    "schemes": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Schemes to build and scan. Required for Xcode projects.",
                        ),
                    ]),
                    "retain_public": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Retain all public declarations. Recommended for library/framework projects. Defaults to false.",
                        ),
                    ]),
                    "skip_build": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Skip the build step and use existing index store data. Faster but requires a prior build. Defaults to false.",
                        ),
                    ]),
                    "exclude_targets": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Targets to exclude from indexing.",
                        ),
                    ]),
                    "report_exclude": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "File globs to exclude from results (e.g. \"**/Generated/**\").",
                        ),
                    ]),
                    "format": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Output format: \"summary\" (default) shows counts by kind and top files; \"detail\" shows per-declaration output grouped by file.",
                        ),
                    ]),
                    "mark": .object([
                        "type": .string("object"),
                        "description": .string(
                            "Mark checklist items by index. Indices are shown as #N in detail output. Properties: indices (array of 1-based integers), status (\"done\"|\"skipped\"|\"false_positive\"|\"pending\"), note (optional string).",
                        ),
                        "properties": .object([
                            "indices": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("integer")]),
                            ]),
                            "status": .object([
                                "type": .string("string"),
                                "enum": .array([
                                    .string("done"), .string("skipped"),
                                    .string("false_positive"), .string("pending"),
                                ]),
                            ]),
                            "note": .object([
                                "type": .string("string"),
                            ]),
                        ]),
                        "required": .array([.string("indices"), .string("status")]),
                    ]),
                    "mark_filtered": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Mark ALL items matching the current filters (kind_filter, file_filter, status_filter) with this status. Eliminates the need to specify indices manually. Value: \"done\"|\"skipped\"|\"false_positive\"|\"pending\".",
                        ),
                        "enum": .array([
                            .string("done"), .string("skipped"),
                            .string("false_positive"), .string("pending"),
                        ]),
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Max declarations to return in detail mode. 0 = no limit. Defaults to 100.",
                        ),
                    ]),
                    "kind_filter": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Filter by declaration kind (e.g. [\"import\", \"func\", \"property\"]). Uses display names from formatKind. Empty = all.",
                        ),
                    ]),
                    "file_filter": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "File path substrings to include (e.g. [\"Admin/\", \"Decoders.swift\"]). Empty = all.",
                        ),
                    ]),
                    "result_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to cached Periphery JSON from a previous scan. Skips the scan entirely and reads results from this file. All filtering and format params still apply.",
                        ),
                    ]),
                    "status_filter": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Filter by checklist status (e.g. [\"pending\"]). Only items with matching status are shown. Valid values: pending, done, skipped, false_positive. Empty = all.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let format = arguments.getString("format") ?? "summary"
        let limit = arguments.getInt("limit") ?? 100
        let kindFilter = arguments.getStringArray("kind_filter")
        let fileFilter = arguments.getStringArray("file_filter")
        let statusFilter = arguments.getStringArray("status_filter")
        let resultFile = arguments.getString("result_file")

        let declarations: [UnusedDeclaration]
        let cachePath: String

        if let resultFile {
            // Read from cached file — skip scan entirely
            let fileURL = URL(fileURLWithPath: resultFile)
            let data = try Data(contentsOf: fileURL)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw MCPError.invalidParams("Could not read result_file as UTF-8")
            }
            declarations = Self.parseJSONOutput(jsonString)
            cachePath = resultFile
        } else {
            // Run Periphery scan
            let (rawJSON, cPath) = try await runPeripheryScan(arguments: arguments)
            declarations = Self.parseJSONOutput(rawJSON)
            cachePath = cPath
        }

        // Always maintain a checklist for iterative cleanup
        let clPath = Self.checklistPath(forCache: cachePath)
        var state: ChecklistState

        if let existing = Self.loadChecklist(path: clPath) {
            state = existing
        } else {
            if declarations.isEmpty {
                return CallTool.Result(content: [.text("No unused code found.")])
            }
            state = Self.createChecklist(from: declarations, cachePath: cachePath)
        }

        // Apply mark actions (by explicit indices)
        if let markAction = Self.parseMarkAction(from: arguments) {
            for index in markAction.indices {
                let zeroIndex = index - 1
                guard zeroIndex >= 0, zeroIndex < state.items.count else { continue }
                state.items[zeroIndex].status = markAction.status
                if let note = markAction.note {
                    state.items[zeroIndex].note = note
                }
            }
        }

        // Apply filters (kind, file, and checklist status)
        let filtered = Self.applyFilters(
            declarations, kindFilter: kindFilter, fileFilter: fileFilter,
            statusFilter: statusFilter, state: state,
        )

        // Apply mark_filtered (mark ALL items matching the current filters)
        let markFilteredStr = arguments.getString("mark_filtered")
        if let markFilteredStr, let markStatus = ChecklistStatus(rawValue: markFilteredStr) {
            let filteredIDs = Set(filtered.map { Self.makeItemID($0) })
            for i in state.items.indices where filteredIDs.contains(state.items[i].id) {
                state.items[i].status = markStatus
            }
        }

        try Self.saveChecklist(state, path: clPath)

        if filtered.isEmpty, declarations.isEmpty {
            return CallTool.Result(content: [.text("No unused code found.")])
        }

        // Build declaration → checklist index map (1-based)
        let indexMap = Self.buildIndexMap(declarations: declarations, state: state)

        let message: String
        if format == "detail" {
            message = Self.formatDetail(
                filtered, limit: limit, totalUnfiltered: declarations.count,
                cachePath: cachePath, checklistPath: clPath, state: state,
                indexMap: indexMap,
            )
        } else {
            message = Self.formatSummary(
                filtered, totalUnfiltered: declarations.count,
                cachePath: cachePath, checklistPath: clPath, state: state,
            )
        }

        return CallTool.Result(content: [.text(message)])
    }

    private func runPeripheryScan(arguments: [String: Value]) async throws -> (
        json: String, cachePath: String,
    ) {
        let project = arguments.getString("project")
        let packagePath: String
        do {
            packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        } catch {
            if let project,
               project.hasSuffix(".xcodeproj") || project.hasSuffix(".xcworkspace")
            {
                let url = URL(fileURLWithPath: project)
                packagePath = url.deletingLastPathComponent().path
            } else {
                throw error
            }
        }
        let schemes = arguments.getStringArray("schemes")
        let retainPublic = arguments.getBool("retain_public")
        let skipBuild = arguments.getBool("skip_build")
        let excludeTargets = arguments.getStringArray("exclude_targets")
        let reportExclude = arguments.getStringArray("report_exclude")

        let executablePath = try await BinaryLocator.find("periphery")

        var args: [String] = [
            "scan",
            "--format", "json",
            "--quiet",
            "--disable-update-check",
            "--project-root", packagePath,
        ]

        if let project {
            args.append("--project")
            args.append(project)
        }

        for scheme in schemes {
            args.append("--schemes")
            args.append(scheme)
        }

        if retainPublic {
            args.append("--retain-public")
        }

        if skipBuild {
            args.append("--skip-build")
        }

        for target in excludeTargets {
            args.append("--exclude-targets")
            args.append(target)
        }

        for glob in reportExclude {
            args.append("--report-exclude")
            args.append(glob)
        }

        do {
            let result = try await ProcessResult.run(
                executablePath, arguments: args, mergeStderr: false,
                timeout: .seconds(600),
            )

            if result.exitCode != 0 {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = stderr.isEmpty ? result.stdout : stderr
                throw MCPError.internalError(
                    "Periphery exited with code \(result.exitCode):\n\(detail)",
                )
            }

            // Cache raw JSON to disk
            let hashInput = "\(packagePath)|\(project ?? "")|\(schemes.joined(separator: ","))"
            let hash = Self.shortHash(hashInput)
            let cacheFile = "/tmp/periphery-\(hash).json"
            try result.stdout.write(
                toFile: cacheFile, atomically: true, encoding: .utf8,
            )

            return (result.stdout, cacheFile)
        } catch let error as MCPError {
            throw error
        } catch {
            throw error.asMCPError()
        }
    }

    static func shortHash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Filtering

    static func applyFilters(
        _ declarations: [UnusedDeclaration],
        kindFilter: [String],
        fileFilter: [String],
        statusFilter: [String] = [],
        state: ChecklistState? = nil,
    ) -> [UnusedDeclaration] {
        if kindFilter.isEmpty, fileFilter.isEmpty, statusFilter.isEmpty { return declarations }

        let statusSet = Set(statusFilter.compactMap { ChecklistStatus(rawValue: $0) })

        return declarations.filter { decl in
            if !kindFilter.isEmpty, !kindFilter.contains(formatKind(decl.kind)) {
                return false
            }
            if !fileFilter.isEmpty, !fileFilter.contains(where: { decl.file.contains($0) }) {
                return false
            }
            if !statusSet.isEmpty, let state {
                let itemID = makeItemID(decl)
                let itemStatus = state.items.first { $0.id == itemID }?.status ?? .pending
                if !statusSet.contains(itemStatus) {
                    return false
                }
            }
            return true
        }
    }

    // MARK: - Models

    struct UnusedDeclaration {
        let name: String
        let kind: String
        let hints: [String]
        let accessibility: String
        let file: String
        let line: Int
        let column: Int
    }

    // MARK: - Checklist Models

    struct ChecklistItem: Codable {
        let id: String
        var status: ChecklistStatus
        var note: String?
    }

    enum ChecklistStatus: String, Codable {
        case pending
        case done
        case skipped
        case falsePositive = "false_positive"
    }

    struct ChecklistState: Codable {
        let version: Int
        let source: String
        var items: [ChecklistItem]
    }

    struct MarkAction {
        let indices: [Int]
        let status: ChecklistStatus
        let note: String?
    }

    private struct PeripheryEntry: Decodable {
        let name: String
        let kind: String
        let hints: [String]
        let accessibility: String?
        let location: String
    }

    // MARK: - Parsing

    static func parseJSONOutput(_ output: String) -> [UnusedDeclaration] {
        guard let data = output.data(using: .utf8),
              let entries = try? JSONDecoder().decode([PeripheryEntry].self, from: data)
        else {
            return []
        }

        return entries.map { entry in
            let (file, line, column) = parseLocation(entry.location)
            return UnusedDeclaration(
                name: entry.name, kind: entry.kind, hints: entry.hints,
                accessibility: entry.accessibility ?? "internal",
                file: file, line: line, column: column,
            )
        }
    }

    static func parseLocation(_ location: String) -> (file: String, line: Int, column: Int) {
        // Format: "/path/to/file.swift:12:6"
        // Split from the right to handle paths that might contain colons
        let parts = location.split(separator: ":")
        guard parts.count >= 3,
              let line = Int(parts[parts.count - 2]),
              let column = Int(parts[parts.count - 1])
        else {
            return (location, 0, 0)
        }
        let file = parts[0 ..< parts.count - 2].joined(separator: ":")
        return (file, line, column)
    }

    // MARK: - Formatting

    static func formatSummary(
        _ declarations: [UnusedDeclaration],
        totalUnfiltered: Int,
        cachePath: String,
        checklistPath: String,
        state: ChecklistState,
    ) -> String {
        let fileCount = Set(declarations.map(\.file)).count
        var lines: [String] = []

        if declarations.count != totalUnfiltered {
            lines.append(
                "\(declarations.count) unused declaration(s) in \(fileCount) file(s) (filtered from \(totalUnfiltered) total)",
            )
        } else {
            lines.append(
                "\(declarations.count) unused declaration(s) in \(fileCount) file(s)",
            )
        }

        // Checklist progress
        lines.append(contentsOf: Self.formatChecklistProgress(state))

        // By kind
        var kindCounts: [String: Int] = [:]
        for d in declarations {
            let displayKind = formatKind(d.kind)
            kindCounts[displayKind, default: 0] += 1
        }
        let sortedKinds = kindCounts.sorted { $0.value > $1.value }
        lines.append("")
        lines.append("By kind:")
        for (kind, count) in sortedKinds {
            lines.append("  \(kind.padding(toLength: 20, withPad: " ", startingAt: 0))\(count)")
        }

        // By file (top 30)
        let fileCounts = Dictionary(grouping: declarations) { $0.file }
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        let topFiles = fileCounts.prefix(30)
        lines.append("")
        lines.append("By file (top \(topFiles.count)):")
        for (file, count) in topFiles {
            let displayPath = Self.compactPath(file)
            lines
                .append(
                    "  \(displayPath.padding(toLength: 60, withPad: " ", startingAt: 0))\(count)",
                )
        }
        if fileCounts.count > 30 {
            lines.append("  ... and \(fileCounts.count - 30) more file(s)")
        }

        lines.append("")
        lines.append("Results cached: \(cachePath)")
        lines.append("Checklist: \(checklistPath)")
        lines.append("Use result_file to drill in without re-scanning. Use mark to track progress.")
        lines.append("")
        lines.append(Self.agentInstructions)

        return lines.joined(separator: "\n")
    }

    static func formatDetail(
        _ declarations: [UnusedDeclaration],
        limit: Int,
        totalUnfiltered: Int,
        cachePath: String,
        checklistPath: String,
        state: ChecklistState,
        indexMap: [String: Int] = [:],
    ) -> String {
        let effectiveLimit = limit == 0 ? declarations.count : limit
        let truncated = declarations.count > effectiveLimit
        let shown = truncated ? Array(declarations.prefix(effectiveLimit)) : declarations

        let grouped = Dictionary(grouping: shown) { $0.file }
        let sortedFiles = grouped.keys.sorted()

        var lines: [String] = []

        if declarations.count != totalUnfiltered {
            lines.append(
                "\(declarations.count) unused declaration(s) (filtered from \(totalUnfiltered) total):\n",
            )
        } else {
            lines.append("\(declarations.count) unused declaration(s) found:\n")
        }

        // Checklist progress
        lines.append(contentsOf: Self.formatChecklistProgress(state))
        lines.append("")

        for file in sortedFiles {
            guard let fileDeclarations = grouped[file] else { continue }
            lines.append(Self.compactPath(file))
            for d in fileDeclarations {
                let hintsStr = d.hints.joined(separator: ", ")
                let kindLabel = Self.formatKind(d.kind)
                let itemID = makeItemID(d)
                let indexLabel = indexMap[itemID].map { "#\($0) " } ?? ""
                lines.append(
                    "  \(indexLabel)\(d.line):\(d.column) \(kindLabel) \(d.name) [\(hintsStr)] (\(d.accessibility))",
                )
            }
        }

        if truncated {
            let omitted = declarations.count - effectiveLimit
            lines.append("")
            lines.append("... \(omitted) more declaration(s) omitted (limit: \(effectiveLimit))")
        }

        lines.append("")
        lines.append("Results cached: \(cachePath)")
        lines.append("Checklist: \(checklistPath)")
        lines.append("Use result_file to drill in without re-scanning. Use mark to track progress.")
        lines.append("")
        lines.append(Self.agentInstructions)

        return lines.joined(separator: "\n")
    }

    // MARK: - Agent Instructions

    static let agentInstructions = """
    For EACH finding: read the code, then either remove it (mark done) or add \
    `// periphery:ignore` above it (mark false_positive). Mark items IMMEDIATELY \
    after resolving — unmarked items reappear as pending.

    Do NOT parse checklist JSON via bash/jq. Use this tool's parameters:
    • Remaining: result_file + status_filter: ["pending"]
    • Filter: kind_filter / file_filter
    • Mark: mark: { indices: [1,2,3], status: "done" } (#N from detail output)
    • Bulk: mark_filtered: "done" (marks all current filter results)
    """

    // MARK: - Checklist Helpers

    static func makeItemID(_ decl: UnusedDeclaration) -> String {
        "\(decl.file):\(decl.line):\(decl.column):\(decl.name)"
    }

    static func checklistPath(forCache cachePath: String) -> String {
        if cachePath.hasSuffix(".json") {
            return String(cachePath.dropLast(5)) + "-checklist.json"
        }
        return cachePath + "-checklist"
    }

    static func loadChecklist(path: String) -> ChecklistState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let state = try? JSONDecoder().decode(ChecklistState.self, from: data)
        else {
            return nil
        }
        return state
    }

    static func saveChecklist(_ state: ChecklistState, path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func createChecklist(
        from declarations: [UnusedDeclaration], cachePath: String,
    ) -> ChecklistState {
        let items = declarations.map { decl in
            ChecklistItem(id: makeItemID(decl), status: .pending)
        }
        return ChecklistState(version: 1, source: cachePath, items: items)
    }

    static func parseMarkAction(from arguments: [String: Value]) -> MarkAction? {
        guard case let .object(markObj) = arguments["mark"],
              case let .array(indicesArray) = markObj["indices"],
              case let .string(statusStr) = markObj["status"],
              let status = ChecklistStatus(rawValue: statusStr)
        else {
            return nil
        }
        let indices = indicesArray.compactMap { value -> Int? in
            if case let .int(i) = value { return i }
            if case let .double(d) = value, d == d.rounded() { return Int(d) }
            return nil
        }
        guard !indices.isEmpty else { return nil }
        var note: String?
        if case let .string(n) = markObj["note"] {
            note = n
        }
        return MarkAction(indices: indices, status: status, note: note)
    }

    /// Maps declaration IDs to their 1-based checklist index.
    static func buildIndexMap(
        declarations: [UnusedDeclaration], state: ChecklistState,
    ) -> [String: Int] {
        // Build reverse lookup: item ID → 1-based index in checklist
        var idToIndex: [String: Int] = [:]
        idToIndex.reserveCapacity(state.items.count)
        for (i, item) in state.items.enumerated() {
            idToIndex[item.id] = i + 1
        }
        // Map declaration IDs to their checklist indices
        var result: [String: Int] = [:]
        result.reserveCapacity(declarations.count)
        for decl in declarations {
            let itemID = makeItemID(decl)
            if let index = idToIndex[itemID] {
                result[itemID] = index
            }
        }
        return result
    }

    static func formatChecklistProgress(_ state: ChecklistState) -> [String] {
        let pendingCount = state.items.count { $0.status == .pending }
        let doneCount = state.items.count { $0.status == .done }
        let skippedCount = state.items.count { $0.status == .skipped }
        let fpCount = state.items.count { $0.status == .falsePositive }

        if doneCount == 0, skippedCount == 0, fpCount == 0 {
            return []
        }

        var parts = ["\(pendingCount) pending"]
        if doneCount > 0 { parts.append("\(doneCount) done") }
        if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
        if fpCount > 0 { parts.append("\(fpCount) false positive") }
        return ["Progress: \(parts.joined(separator: ", "))"]
    }

    static func formatKind(_ kind: String) -> String {
        switch kind {
            case "function.free": return "func"
            case "function.method.instance": return "method"
            case "function.method.static": return "static method"
            case "function.method.class": return "class method"
            case "var.instance": return "property"
            case "var.static": return "static property"
            case "var.global": return "var"
            case "enumelement": return "case"
            case "typealias": return "typealias"
            case "import": return "import"
            default: return kind
        }
    }

    /// Strips common path prefixes for compact display.
    static func compactPath(_ path: String) -> String {
        // Strip /Users/username/... down to ~/...
        if path.hasPrefix("/Users/") {
            let afterUsers = path.dropFirst(7) // "/Users/"
            if let slashIndex = afterUsers.firstIndex(of: "/") {
                return "~" + afterUsers[slashIndex...]
            }
        }
        return path
    }
}
