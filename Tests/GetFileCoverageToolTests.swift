import Testing
@testable import XCMCPCore
@testable import XCMCPTools
import Foundation

@Suite("GetFileCoverageTool Tests")
struct GetFileCoverageToolTests {
    @Test("Format file coverage with function breakdown")
    func formatFileCoverage() throws {
        let coverage = FileFunctionCoverage(
            path: "/path/to/MyFile.swift",
            lineCoverage: 65.3,
            coveredLines: 32,
            executableLines: 49,
            functions: [
                FunctionCoverage(
                    name: "init()",
                    lineNumber: 12,
                    coveredLines: 5,
                    executableLines: 5,
                    lineCoverage: 100.0,
                    executionCount: 3,
                ),
                FunctionCoverage(
                    name: "calculate(_:)",
                    lineNumber: 25,
                    coveredLines: 8,
                    executableLines: 10,
                    lineCoverage: 80.0,
                    executionCount: 2,
                ),
                FunctionCoverage(
                    name: "unusedHelper()",
                    lineNumber: 45,
                    coveredLines: 0,
                    executableLines: 12,
                    lineCoverage: 0.0,
                    executionCount: 0,
                ),
            ],
        )

        let output = GetFileCoverageTool.formatFileCoverage(coverage)

        #expect(output.contains("File Coverage: /path/to/MyFile.swift"))
        #expect(output.contains("Coverage: 65.3%"))
        #expect(output.contains("[NOT COVERED]"))
        #expect(output.contains("unusedHelper()"))
        #expect(output.contains("called 3x"))
        // Uncovered functions should appear first
        let uncoveredIndex = try #require(output.range(of: "unusedHelper")?.lowerBound)
        let initIndex = try #require(output.range(of: "init()")?.lowerBound)
        #expect(uncoveredIndex < initIndex)
    }

    @Test("Format uncovered ranges single and multi-line")
    func formatUncoveredRanges() {
        let ranges = [
            UncoveredRange(start: 10, end: 10),
            UncoveredRange(start: 25, end: 30),
        ]

        let output = GetFileCoverageTool.formatUncoveredRanges(ranges)

        #expect(output.contains("L10"))
        #expect(!output.contains("L10-"))
        #expect(output.contains("L25-30"))
    }

    @Test("Execute with non-existent bundle path throws")
    func executeWithBadPath() async {
        let tool = GetFileCoverageTool()
        do {
            _ = try await tool.execute(arguments: [
                "result_bundle_path": .string("/nonexistent/path.xcresult"),
                "file": .string("/path/to/file.swift"),
            ])
            Issue.record("Expected MCPError to be thrown")
        } catch {
            #expect(String(describing: error).contains("not found"))
        }
    }

    @Test("Execute with missing file param throws")
    func executeMissingFile() async {
        let tool = GetFileCoverageTool()
        do {
            _ = try await tool.execute(arguments: [
                "result_bundle_path": .string("/some/path.xcresult"),
            ])
            Issue.record("Expected MCPError to be thrown")
        } catch {
            #expect(String(describing: error).contains("required"))
        }
    }
}
