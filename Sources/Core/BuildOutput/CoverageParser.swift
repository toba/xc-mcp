// Adapted from xcsift (MIT License) - https://github.com/ldomaradzki/xcsift
// swiftlint:disable legacy_objc_type
import Foundation
import Subprocess

/// Parses code coverage data from `.xcresult` bundles and SPM `.profraw` files.
public struct CoverageParser: Sendable {
    public init() {}

    // MARK: - Main Entry Point

    /// Parses coverage from a path (xcresult bundle, JSON file, or directory to search).
    public func parseCoverageFromPath(
        _ path: String,
        targetFilter: String? = nil,
    ) async -> CodeCoverage? {
        let fileManager = FileManager.default
        let coveragePath: String

        if !path.isEmpty, fileManager.fileExists(atPath: path) {
            coveragePath = path
        } else if !path.isEmpty {
            // An explicit path was provided but does not exist — do not fall back to ambient
            // defaults; the caller wanted that exact location.
            return nil
        } else {
            if let latestXCResult =
                await findLatestXCResultInDerivedData(projectHint: targetFilter)
            {
                return await convertXCResultToJSON(
                    xcresultPath: latestXCResult, targetFilter: targetFilter,
                )
            }

            let defaultPaths = [
                ".build/debug/codecov",
                ".build/arm64-apple-macosx/debug/codecov",
                ".build/x86_64-apple-macosx/debug/codecov",
                "DerivedData",
                ".",
            ]

            var foundPath: String?

            for defaultPath in defaultPaths where fileManager.fileExists(atPath: defaultPath) {
                foundPath = defaultPath
                break
            }

            guard let found = foundPath else { return nil }
            coveragePath = found
        }

        guard fileManager.fileExists(atPath: coveragePath) else { return nil }

        var isDirectory: ObjCBool = false
        _ = fileManager.fileExists(atPath: coveragePath, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            guard let files = try? fileManager.contentsOfDirectory(atPath: coveragePath) else {
                return nil
            }

            let jsonFiles = files.filter { $0.hasSuffix(".json") }

            if let firstJsonFile = jsonFiles.first {
                let jsonPath = (coveragePath as NSString).appendingPathComponent(firstJsonFile)
                return parseCoverageJSON(at: jsonPath, targetFilter: targetFilter)
            }

            let profrawFiles = findProfrawFiles(in: coveragePath)

            if !profrawFiles.isEmpty {
                return await convertProfrawToJSON(profrawFiles: profrawFiles)
            }

            let xcresultBundles = findXCResultBundles(in: coveragePath)

            if let firstXCResult = xcresultBundles.first {
                return await convertXCResultToJSON(
                    xcresultPath: firstXCResult, targetFilter: targetFilter,
                )
            }

            if let latestXCResult = await findLatestXCResultInDerivedData() {
                return await convertXCResultToJSON(
                    xcresultPath: latestXCResult, targetFilter: targetFilter,
                )
            }

            return nil
        } else {
            return coveragePath.hasSuffix(".xcresult")
                ? await convertXCResultToJSON(
                    xcresultPath: coveragePath, targetFilter: targetFilter,
                )
                : parseCoverageJSON(at: coveragePath, targetFilter: targetFilter)
        }
    }

    // MARK: - Auto-Detection Helpers

    private func findProfrawFiles(in directory: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var profrawFiles: [String] = []

        for case let file as String in enumerator where file.hasSuffix(".profraw") {
            let fullPath = (directory as NSString).appendingPathComponent(file)
            profrawFiles.append(fullPath)
        }
        return profrawFiles
    }

    private func findXCResultBundles(in directory: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var xcresultPaths: [String] = []

        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".xcresult") {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                xcresultPaths.append(fullPath)
                enumerator.skipDescendants()
            }
        }
        return xcresultPaths
    }

    private func findLatestXCResultInDerivedData(projectHint: String? = nil) async -> String? {
        let homeDir = NSHomeDirectory()
        let derivedDataPath = (homeDir as NSString).appendingPathComponent(
            "Library/Developer/Xcode/DerivedData",
        )

        guard FileManager.default.fileExists(atPath: derivedDataPath) else { return nil }

        let searchPaths: [String]

        if let hint = projectHint {
            // sm:ignore useLazyForLongChainOps
            let projectDirs =
                (try? FileManager.default.contentsOfDirectory(atPath: derivedDataPath))?
                .filter { $0.hasPrefix("\(hint)-") || $0.hasPrefix("\(hint)Tests-") }
                .map { (derivedDataPath as NSString).appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0) }

            guard let dirs = projectDirs, !dirs.isEmpty else { return nil }
            searchPaths = dirs
        } else {
            searchPaths = [derivedDataPath]
        }

        let findArgs = ["find"] + searchPaths + [
            "-name", "*.xcresult", "-type", "d", "-mtime", "-7",
        ]
        guard let output = await runShellCommand("/usr/bin/env", args: findArgs) else { return nil }

        let paths = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !paths.isEmpty else { return nil }

        var newestBundle: String?
        var newestDate: Date?

        for path in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                let modDate = attrs[.modificationDate] as? Date
            {
                if newestDate.map({ modDate > $0 }) ?? true {
                    newestDate = modDate
                    newestBundle = path
                }
            }
        }

        return newestBundle
    }

    private func findTestBinary() -> String? {
        let buildDir = ".build"

        guard FileManager.default.fileExists(atPath: buildDir),
            let enumerator = FileManager.default.enumerator(atPath: buildDir) else { return nil }

        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".xctest") {
                let xctestPath = (buildDir as NSString).appendingPathComponent(file)
                let macosPath = (xctestPath as NSString).appendingPathComponent("Contents/MacOS")

                enumerator.skipDescendants()

                guard let macosContents = try? FileManager.default.contentsOfDirectory(
                    atPath: macosPath,
                ) else { continue }

                for item in macosContents {
                    let itemPath = (macosPath as NSString).appendingPathComponent(item)
                    var isDirectory: ObjCBool = false

                    if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                        !isDirectory.boolValue,
                        !item.hasSuffix(".dSYM") { return itemPath }
                }
            }
        }
        return nil
    }

    // MARK: - Conversion Helpers

    private func convertProfrawToJSON(profrawFiles: [String]) async -> CodeCoverage? {
        guard !profrawFiles.isEmpty else { return nil }
        guard let testBinary = findTestBinary() else { return nil }

        let tempDir = NSTemporaryDirectory()
        let profdataPath = (tempDir as NSString).appendingPathComponent("xc-mcp-coverage.profdata")
        let jsonPath = (tempDir as NSString).appendingPathComponent("xc-mcp-coverage.json")

        let mergeArgs = ["llvm-profdata", "merge", "-sparse"] + profrawFiles + ["-o", profdataPath]
        guard await runShellCommand("xcrun", args: mergeArgs) != nil else { return nil }

        let exportArgs = [
            "llvm-cov", "export", testBinary, "-instr-profile=\(profdataPath)", "-format=text",
        ]
        guard let jsonOutput = await runShellCommand("xcrun", args: exportArgs) else {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }

        let jsonData = Data(jsonOutput.utf8)

        do {
            try jsonData.write(to: URL(fileURLWithPath: jsonPath))
            let coverage = parseCoverageJSON(at: jsonPath)
            try? FileManager.default.removeItem(atPath: profdataPath)
            try? FileManager.default.removeItem(atPath: jsonPath)
            return coverage
        } catch {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }
    }

    private func convertXCResultToJSON(
        xcresultPath: String,
        targetFilter: String? = nil
    )
        async -> CodeCoverage?
    {
        guard let jsonData = await runXccovReport(xcresultPath: xcresultPath) else { return nil }
        return Self.parseXcodebuildFormat(jsonData: jsonData, targetFilter: targetFilter)
    }

    /// Runs `xcrun xccov view --report --json` and returns the raw JSON output as `Data`.
    private func runXccovReport(xcresultPath: String) async -> Data? {
        let args = ["xccov", "view", "--report", "--json", xcresultPath]
        guard let jsonOutput = await runShellCommand("xcrun", args: args) else { return nil }
        return Data(jsonOutput.utf8)
    }

    // MARK: - JSON Parsing

    /// xccov report JSON: `{ "targets": [ { "name", "files": [...] } ] }` .
    private struct XccovReport: Decodable {
        let targets: [XccovTarget]
    }

    private struct XccovTarget: Decodable {
        let name: String?
        let files: [XccovFile]?
    }

    private struct XccovFile: Decodable {
        let path: String
        let lineCoverage: Double
        let coveredLines: Int?
        let executableLines: Int?
    }

    /// SPM `llvm-cov export` JSON: `{ "data": [ { "files": [ { "filename", "summary" } ] } ] }` .
    private struct SPMReport: Decodable {
        let data: [SPMData]
    }

    private struct SPMData: Decodable {
        let files: [SPMFile]
    }

    private struct SPMFile: Decodable {
        let filename: String
        let summary: SPMSummary
    }

    private struct SPMSummary: Decodable {
        let lines: SPMLines
    }

    private struct SPMLines: Decodable {
        let covered: Int
        let count: Int
    }

    /// One function entry from `xccov view --functions-for-file --json` .
    private struct XccovFunction: Decodable {
        let name: String
        let lineNumber: Int?
        let coveredLines: Int?
        let executableLines: Int?
        let lineCoverage: Double?
        let executionCount: Int?
    }

    /// The object form of function coverage: `{ "functions": [...] }` .
    private struct XccovFunctionsWrapper: Decodable {
        let functions: [XccovFunction]
    }

    /// Extracted file data from either Xcode or SPM JSON format.
    private struct RawFileCoverage {
        let path: String
        let coveredLines: Int
        let executableLines: Int
        let lineCoverage: Double
    }

    /// Normalizes xccov line coverage (0.0–1.0 fraction or 0–100 percentage) to percentage.
    static func normalizeLineCoverage(_ coverage: Double) -> Double {
        coverage > 1.0 ? coverage : coverage * 100.0
    }

    /// Computes overall coverage percentage from covered/executable line counts.
    static func coveragePercent(covered: Int, executable: Int) -> Double {
        executable > 0 ? (Double(covered) / Double(executable)) * 100.0 : 0.0
    }

    /// Parses a single xccov file entry into a ``FileCoverage``.
    private static func parseFileEntry(_ file: XccovFile) -> FileCoverage {
        .init(
            path: file.path,
            name: (file.path as NSString).lastPathComponent,
            lineCoverage: normalizeLineCoverage(file.lineCoverage),
            coveredLines: file.coveredLines ?? 0,
            executableLines: file.executableLines ?? 0,
        )
    }

    /// Aggregates file coverage entries into a CodeCoverage result.
    private static func aggregate(_ entries: [RawFileCoverage]) -> CodeCoverage? {
        guard !entries.isEmpty else { return nil }
        var totalCovered = 0
        var totalExecutable = 0
        var fileCoverages: [FileCoverage] = []
        fileCoverages.reserveCapacity(entries.count)

        for entry in entries {
            let name = (entry.path as NSString).lastPathComponent
            fileCoverages.append(FileCoverage(
                path: entry.path, name: name, lineCoverage: entry.lineCoverage,
                coveredLines: entry.coveredLines, executableLines: entry.executableLines,
            ))
            totalCovered += entry.coveredLines
            totalExecutable += entry.executableLines
        }
        return CodeCoverage(
            lineCoverage: coveragePercent(covered: totalCovered, executable: totalExecutable),
            files: fileCoverages,
        )
    }

    private func parseCoverageJSON(at path: String, targetFilter: String? = nil) -> CodeCoverage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }

        if let coverage = Self.parseXcodebuildFormat(jsonData: data, targetFilter: targetFilter) {
            return coverage
        }

        return Self.parseSPMFormat(jsonData: data)
    }

    private static func parseXcodebuildFormat(
        jsonData: Data,
        targetFilter: String? = nil
    ) -> CodeCoverage? {
        guard let report = try? JSONDecoder().decode(XccovReport.self, from: jsonData) else {
            return nil
        }

        var entries: [RawFileCoverage] = []

        for target in report.targets {
            if let name = target.name, name.hasSuffix(".xctest") { continue }

            if let filter = targetFilter, let name = target.name {
                if !name.contains(filter), !filter.contains(name) { continue }
            }

            for file in target.files ?? [] {
                let coverage = parseFileEntry(file)
                entries.append(RawFileCoverage(
                    path: coverage.path, coveredLines: coverage.coveredLines,
                    executableLines: coverage.executableLines, lineCoverage: coverage.lineCoverage,
                ))
            }
        }

        return aggregate(entries)
    }

    private static func parseSPMFormat(jsonData: Data) -> CodeCoverage? {
        guard let report = try? JSONDecoder().decode(SPMReport.self, from: jsonData),
              let firstData = report.data.first else { return nil }

        var entries: [RawFileCoverage] = []

        for file in firstData.files {
            let covered = file.summary.lines.covered
            let count = file.summary.lines.count
            let coverage = count > 0 ? (Double(covered) / Double(count)) * 100.0 : 0.0

            entries.append(RawFileCoverage(
                path: file.filename, coveredLines: covered, executableLines: count,
                lineCoverage: coverage,
            ))
        }

        return aggregate(entries)
    }

    // MARK: - Coverage Report (Target-Level)

    /// Parses an xcresult bundle and returns per-target coverage data.
    ///
    /// - Parameters:
    ///   - xcresultPath: Path to the .xcresult bundle.
    ///   - targetFilter: Optional case-insensitive substring filter for target names.
    /// - Returns: A ``CoverageReport`` with per-target breakdown, or nil on failure.
    public func parseCoverageReport(
        xcresultPath: String,
        targetFilter: String? = nil,
    ) async -> CoverageReport? {
        guard let jsonData = await runXccovReport(xcresultPath: xcresultPath) else { return nil }
        return Self.parseTargetCoverage(jsonData: jsonData, targetFilter: targetFilter)
    }

    /// Parses xccov JSON into target-level coverage. Visible for testing.
    static func parseTargetCoverage(
        jsonData: Data,
        targetFilter: String? = nil,
    ) -> CoverageReport? {
        guard let report = try? JSONDecoder().decode(XccovReport.self, from: jsonData) else {
            return nil
        }

        let lowercaseFilter = targetFilter?.lowercased()
        var targetCoverages: [TargetCoverage] = []
        var totalCovered = 0
        var totalExecutable = 0

        for target in report.targets {
            guard let targetName = target.name else { continue }

            if targetName.hasSuffix(".xctest") { continue }

            if let filter = lowercaseFilter {
                if !targetName.lowercased().contains(filter) { continue }
            }

            let filesArray = target.files ?? []

            var files: [FileCoverage] = []
            files.reserveCapacity(filesArray.count)
            var targetCovered = 0
            var targetExecutable = 0

            for fileData in filesArray {
                let file = parseFileEntry(fileData)
                files.append(file)
                targetCovered += file.coveredLines
                targetExecutable += file.executableLines
            }

            targetCoverages.append(TargetCoverage(
                name: targetName,
                lineCoverage: coveragePercent(covered: targetCovered, executable: targetExecutable),
                coveredLines: targetCovered, executableLines: targetExecutable, files: files,
            ))
            totalCovered += targetCovered
            totalExecutable += targetExecutable
        }

        guard !targetCoverages.isEmpty else { return nil }

        return CoverageReport(
            lineCoverage: coveragePercent(covered: totalCovered, executable: totalExecutable),
            coveredLines: totalCovered,
            executableLines: totalExecutable,
            targets: targetCoverages,
        )
    }

    // MARK: - Function-Level Coverage

    /// Parses function-level coverage for a specific file from an xcresult bundle.
    ///
    /// - Parameters:
    ///   - xcresultPath: Path to the .xcresult bundle.
    ///   - filePath: Source file path to query.
    /// - Returns: A ``FileFunctionCoverage`` with function breakdown, or nil on failure.
    public func parseFunctionCoverage(
        xcresultPath: String,
        filePath: String,
    ) async -> FileFunctionCoverage? {
        let args = [
            "xccov", "view", "--report", "--functions-for-file", filePath, "--json", xcresultPath,
        ]
        guard let jsonOutput = await runShellCommand("xcrun", args: args) else { return nil }

        let jsonData = Data(jsonOutput.utf8)
        return Self.parseFunctionCoverageJSON(jsonData: jsonData, filePath: filePath)
    }

    /// Parses function-level coverage JSON data. Visible for testing.
    static func parseFunctionCoverageJSON(
        jsonData: Data,
        filePath: String,
    ) -> FileFunctionCoverage? {
        // xccov --functions-for-file returns an array of function entries or an object with a
        // "functions" key depending on the file match
        let decoder = JSONDecoder()
        let functions: [XccovFunction]

        if let array = try? decoder.decode([XccovFunction].self, from: jsonData) {
            functions = array
        } else if let wrapper = try? decoder.decode(XccovFunctionsWrapper.self, from: jsonData) {
            functions = wrapper.functions
        } else {
            return nil
        }

        guard !functions.isEmpty else { return nil }

        var functionCoverages: [FunctionCoverage] = []
        functionCoverages.reserveCapacity(functions.count)
        var totalCovered = 0
        var totalExecutable = 0

        for fn in functions {
            let covered = fn.coveredLines ?? 0
            let executable = fn.executableLines ?? 0

            functionCoverages.append(FunctionCoverage(
                name: fn.name, lineNumber: fn.lineNumber ?? 0, coveredLines: covered,
                executableLines: executable,
                lineCoverage: normalizeLineCoverage(fn.lineCoverage ?? 0.0),
                executionCount: fn.executionCount ?? 0,
            ))
            totalCovered += covered
            totalExecutable += executable
        }

        return FileFunctionCoverage(
            path: filePath,
            lineCoverage: coveragePercent(covered: totalCovered, executable: totalExecutable),
            coveredLines: totalCovered,
            executableLines: totalExecutable,
            functions: functionCoverages,
        )
    }

    // MARK: - Uncovered Line Ranges

    /// Parses uncovered line ranges from the xcresult archive for a specific file.
    ///
    /// - Parameters:
    ///   - xcresultPath: Path to the .xcresult bundle.
    ///   - filePath: Source file path to query.
    /// - Returns: An array of ``UncoveredRange`` values, or nil on failure.
    public func parseUncoveredLines(
        xcresultPath: String,
        filePath: String,
    ) async -> [UncoveredRange]? {
        let args = ["xccov", "view", "--archive", "--file", filePath, xcresultPath]
        guard let output = await runShellCommand("xcrun", args: args) else { return nil }

        return Self.parseUncoveredLinesFromArchive(output)
    }

    /// Parses uncovered line ranges from xccov archive output. Visible for testing.
    ///
    /// The archive format has lines like:
    /// ```
    ///    1: *
    ///    2: 1
    ///    3: 0
    ///    4: 0
    ///    5: 1
    /// ```
    /// where `0` means uncovered and `*` means non-executable.
    static func parseUncoveredLinesFromArchive(_ output: String) -> [UncoveredRange] {
        var ranges: [UncoveredRange] = []
        var rangeStart: Int?
        var lastLineNumber: Int?

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let lineNumberStr = trimmed[trimmed.startIndex..<colonIndex]
                .trimmingCharacters(in: .whitespaces)
            let countStr = trimmed[trimmed.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)

            guard let lineNumber = Int(lineNumberStr) else { continue }
            lastLineNumber = lineNumber

            if countStr == "0" {
                if rangeStart == nil { rangeStart = lineNumber }
            } else {
                if let start = rangeStart {
                    ranges.append(UncoveredRange(start: start, end: lineNumber - 1))
                    rangeStart = nil
                }
            }
        }

        // Close any trailing uncovered range
        if let start = rangeStart {
            ranges.append(UncoveredRange(start: start, end: lastLineNumber ?? start))
        }

        return ranges
    }

    // MARK: - Shell Helpers

    @discardableResult
    private func runShellCommand(_ command: String, args: [String]) async -> String? {
        guard let result = try? await ProcessResult.runSubprocess(
            .name(command),
            arguments: Arguments(args),
            mergeStderr: true,
        ),
              result.succeeded else { return nil }
        return result.stdout
    }
}
