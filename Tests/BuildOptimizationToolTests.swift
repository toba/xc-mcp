import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

// MARK: - BenchmarkBuildTool

@Suite(.temporaryDirectory)
struct BenchmarkBuildToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = BenchmarkBuildTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "benchmark_build")
        #expect(schema.description?.contains("wall-clock") == true)
    }

    @Test
    func `Tool schema exposes clean and incremental run counts`() {
        let tool = BenchmarkBuildTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }
        #expect(properties["clean_runs"] != nil)
        #expect(properties["incremental_runs"] != nil)
        #expect(properties["save_baseline"] != nil)
        #expect(properties["compare_baseline"] != nil)
    }

    @Test
    func `stats computes mean min max and stddev`() {
        let stats = BenchmarkBuildTool.stats([2, 4, 6])
        #expect(stats?.count == 3)
        #expect(stats?.mean == 4)
        #expect(stats?.min == 2)
        #expect(stats?.max == 6)
        // Population stddev of [2,4,6] is sqrt(8/3) ≈ 1.633.
        #expect(abs((stats?.stddev ?? 0) - 1.632_993) < 0.0001)
    }

    @Test
    func `stats returns nil for empty input`() { #expect(BenchmarkBuildTool.stats([]) == nil) }

    @Test
    func `parseTimingSummary extracts and sorts phases by cost`() {
        let output = """
            Build Timing Summary

            Ld (1 task) | 0.456 seconds
            CompileSwiftSources (12 tasks) | 34.567 seconds
            PhaseScriptExecution (2 tasks) | 1.200 seconds
            unrelated line that should be ignored
            """
        let phases = BenchmarkBuildTool.parseTimingSummary(output)
        #expect(phases.count == 3)
        // Sorted descending by seconds.
        #expect(phases.first?.phase == "CompileSwiftSources")
        #expect(phases.first?.tasks == 12)
        #expect(phases.first?.seconds == 34.567)
        #expect(phases.last?.phase == "Ld")
    }

    @Test
    func `baselineURL sanitizes scheme and configuration into the build-benchmark dir`() {
        let url = BenchmarkBuildTool.baselineURL(
            anchorPath: "/tmp/proj/App.xcodeproj", scheme: "My App", configuration: "Debug",
        )
        #expect(url.path == "/tmp/proj/.build-benchmark/My-App_Debug.json")
    }

    @Test
    func `baseline save and load round-trips`() throws {
        let dir = TemporaryDirectory.url
        let url = dir.appendingPathComponent("baseline.json")
        let record = BenchmarkBuildTool.BenchmarkRecord(
            scheme: "App", configuration: "Debug",
            cleanSeconds: [10, 11], incrementalSeconds: [1, 1.2],
            machine: "Apple M3", timestamp: "2026-07-26T00:00:00Z",
        )
        let saved = BenchmarkBuildTool.saveBaseline(record, to: url)
        #expect(saved == url.path)

        let loaded = BenchmarkBuildTool.loadBaseline(at: url)
        #expect(loaded?.scheme == "App")
        #expect(loaded?.cleanSeconds == [10, 11])
        #expect(loaded?.incrementalSeconds == [1, 1.2])

        try? FileManager.default.removeItem(at: dir)
    }

    @Test
    func `report includes baseline comparison when provided`() {
        let prior = BenchmarkBuildTool.BenchmarkRecord(
            scheme: "App", configuration: "Debug",
            cleanSeconds: [20], incrementalSeconds: [2],
            machine: "Apple M3", timestamp: "2026-07-01T00:00:00Z",
        )
        let text = BenchmarkBuildTool.formatReport(
            scheme: "App", configuration: "Debug",
            cleanSeconds: [10], incrementalSeconds: [1],
            timingSummary: [], priorBaseline: prior, savedTo: nil,
        )
        #expect(text.contains("vs baseline mean"))
        #expect(text.contains("faster"))
    }
}

// MARK: - FindCompileHotspotsTool

struct FindCompileHotspotsToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and is read-only`() {
        let tool = FindCompileHotspotsTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "find_compile_hotspots")
        #expect(schema.annotations.readOnlyHint == true)
    }

    @Test
    func `parseHotspots extracts expression and function-body warnings`() {
        let output = """
            /proj/Sources/A.swift:12:5: warning: expression took 152ms to type-check (limit: 100ms)
            /proj/Sources/B.swift:40:1: warning: instance method 'foo()' took 210ms to type-check (limit: 100ms)
            /proj/Sources/A.swift:99:3: note: something unrelated
            """
        let hotspots = FindCompileHotspotsTool.parseHotspots(output, projectRoot: "/proj")
        #expect(hotspots.count == 2)
        // Ranked slowest first.
        #expect(hotspots[0].milliseconds == 210)
        #expect(hotspots[0].kind == .functionBody)
        #expect(hotspots[0].file == "Sources/B.swift")
        #expect(hotspots[1].kind == .expression)
        #expect(hotspots[1].file == "Sources/A.swift")
    }

    @Test
    func `parseHotspots keeps the worst duplicate per site`() {
        let output = """
            /proj/A.swift:1:1: warning: expression took 100ms to type-check (limit: 50ms)
            /proj/A.swift:1:1: warning: expression took 180ms to type-check (limit: 50ms)
            """
        let hotspots = FindCompileHotspotsTool.parseHotspots(output, projectRoot: "/proj")
        #expect(hotspots.count == 1)
        #expect(hotspots[0].milliseconds == 180)
    }

    @Test
    func `fileTotals aggregates cost per file`() {
        let hotspots = [
            FindCompileHotspotsTool.Hotspot(
                file: "A.swift", line: 1, column: 1, kind: .expression,
                description: "expression", milliseconds: 100,
            ),
            FindCompileHotspotsTool.Hotspot(
                file: "A.swift", line: 2, column: 1, kind: .expression,
                description: "expression", milliseconds: 50,
            ),
            FindCompileHotspotsTool.Hotspot(
                file: "B.swift", line: 1, column: 1, kind: .functionBody,
                description: "func", milliseconds: 200,
            ),
        ]
        let totals = FindCompileHotspotsTool.fileTotals(hotspots)
        #expect(totals.first?.file == "B.swift")
        #expect(totals.first?.totalMs == 200)
        #expect(totals.last?.file == "A.swift")
        #expect(totals.last?.totalMs == 150)
        #expect(totals.last?.count == 2)
    }

    @Test
    func `report notes when nothing exceeds the threshold`() {
        let text = FindCompileHotspotsTool.formatReport(
            hotspots: [], thresholdMs: 100, limit: 25, buildSucceeded: true,
        )
        #expect(text.contains("No functions or expressions exceeded"))
    }
}

// MARK: - AuditBuildSettingsTool

struct AuditBuildSettingsToolTests {
    let sessionManager = SessionManager()
    let pathUtility = PathUtility(basePath: FileManager.default.currentDirectoryPath)

    @Test
    func `Tool schema has correct name and is read-only`() {
        let tool = AuditBuildSettingsTool(sessionManager: sessionManager, pathUtility: pathUtility)
        let schema = tool.tool()
        #expect(schema.name == "audit_build_settings")
        #expect(schema.annotations.readOnlyHint == true)
    }

    @Test
    func `optimal Debug settings produce no findings`() {
        let settings = [
            "SWIFT_COMPILATION_MODE": "incremental",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        ]
        let findings = AuditBuildSettingsTool.auditSettings(settings, configuration: "Debug")
        #expect(findings.isEmpty)
    }

    @Test
    func `flags whole-module dsym all-arch and optimization in Debug`() {
        let settings = [
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "ONLY_ACTIVE_ARCH": "NO",
        ]
        let findings = AuditBuildSettingsTool.auditSettings(settings, configuration: "Debug")
        let titles = findings.map(\.title)
        #expect(titles.contains("Whole-module compilation in Debug"))
        #expect(titles.contains("Swift optimization enabled in Debug"))
        #expect(titles.contains("dSYM generation in Debug"))
        #expect(titles.contains("Building all architectures in Debug"))
        #expect(findings.allSatisfy { $0.severity == .warning })
    }

    @Test
    func `Release configuration is not flagged for whole-module or optimization`() {
        let settings = [
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        ]
        let findings = AuditBuildSettingsTool.auditSettings(settings, configuration: "Release")
        #expect(findings.isEmpty)
    }

    @Test
    func `explicit modules and eager linking flagged only when explicitly off`() {
        let off = [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
            "SWIFT_ENABLE_EXPLICIT_MODULES": "NO",
            "EAGER_LINKING": "NO",
        ]
        let findings = AuditBuildSettingsTool.auditSettings(off, configuration: "Debug")
        let titles = findings.map(\.title)
        #expect(titles.contains("Explicit modules disabled"))
        #expect(titles.contains("Eager linking disabled"))
        #expect(findings.allSatisfy { $0.severity == .info })

        // Absent (unset) values must not be flagged — avoids noise from Xcode defaults.
        let absent = ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"]
        #expect(AuditBuildSettingsTool.auditSettings(absent, configuration: "Debug").isEmpty)
    }

    @Test
    func `isDebugConfiguration recognizes DEBUG condition on non-Debug config name`() {
        let settings = ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG TESTING"]
        #expect(AuditBuildSettingsTool.isDebugConfiguration(settings, configuration: "Dev"))
        #expect(!AuditBuildSettingsTool.isDebugConfiguration([:], configuration: "Release"))
    }

    @Test
    func `parseSettings reads JSON output`() {
        let json = """
            [{"target":"App","buildSettings":{"ONLY_ACTIVE_ARCH":"YES","PRODUCT_NAME":"App"}}]
            """
        let settings = BuildSettingExtractor.parseSettings(from: json)
        #expect(settings["ONLY_ACTIVE_ARCH"] == "YES")
        #expect(settings["PRODUCT_NAME"] == "App")
    }

    @Test
    func `report renders findings sorted by severity`() {
        let findings = [
            AuditBuildSettingsTool.Finding(
                severity: .info, title: "Info item", detail: "d", recommendation: "r",
            ),
            AuditBuildSettingsTool.Finding(
                severity: .warning, title: "Warning item", detail: "d", recommendation: "r",
            ),
        ]
        let text = AuditBuildSettingsTool.formatReport(
            findings: findings, scheme: "App", configuration: "Debug",
        )
        guard let warnIdx = text.range(of: "Warning item"),
              let infoIdx = text.range(of: "Info item")
        else {
            Issue.record("Expected both findings in report")
            return
        }
        #expect(warnIdx.lowerBound < infoIdx.lowerBound)
        #expect(text.contains("(1 warning)"))
    }

    @Test
    func `report is near-empty when no findings`() {
        let text = AuditBuildSettingsTool.formatReport(
            findings: [], scheme: "App", configuration: "Debug",
        )
        #expect(text.contains("No incremental-build anti-patterns detected"))
    }
}
