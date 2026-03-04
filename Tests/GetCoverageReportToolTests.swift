import Testing
@testable import XCMCPCore
@testable import XCMCPTools
import Foundation

struct GetCoverageReportToolTests {
    @Test
    func `Format report with multiple targets sorted by coverage ascending`() throws {
        let report = CoverageReport(
            lineCoverage: 72.3,
            coveredLines: 1450,
            executableLines: 2005,
            targets: [
                TargetCoverage(
                    name: "MyApp",
                    lineCoverage: 85.8,
                    coveredLines: 1150,
                    executableLines: 1341,
                    files: [
                        FileCoverage(
                            path: "/path/to/AppDelegate.swift",
                            name: "AppDelegate.swift",
                            lineCoverage: 90.0,
                            coveredLines: 900,
                            executableLines: 1000,
                        ),
                    ],
                ),
                TargetCoverage(
                    name: "MyFramework",
                    lineCoverage: 45.2,
                    coveredLines: 300,
                    executableLines: 664,
                    files: [
                        FileCoverage(
                            path: "/path/to/Utility.swift",
                            name: "Utility.swift",
                            lineCoverage: 45.2,
                            coveredLines: 300,
                            executableLines: 664,
                        ),
                    ],
                ),
            ],
        )

        let output = GetCoverageReportTool.formatReport(report, showFiles: false)

        #expect(output.contains("Overall: 72.3%"))
        #expect(output.contains("1450/2005"))
        // MyFramework (45.2%) should come before MyApp (85.8%)
        let frameworkIndex = try #require(output.range(of: "MyFramework")?.lowerBound)
        let appIndex = try #require(output.range(of: "MyApp")?.lowerBound)
        #expect(frameworkIndex < appIndex)
    }

    @Test
    func `Format report with show_files includes file breakdown`() throws {
        let report = CoverageReport(
            lineCoverage: 80.0,
            coveredLines: 80,
            executableLines: 100,
            targets: [
                TargetCoverage(
                    name: "MyTarget",
                    lineCoverage: 80.0,
                    coveredLines: 80,
                    executableLines: 100,
                    files: [
                        FileCoverage(
                            path: "/path/to/A.swift",
                            name: "A.swift",
                            lineCoverage: 60.0,
                            coveredLines: 30,
                            executableLines: 50,
                        ),
                        FileCoverage(
                            path: "/path/to/B.swift",
                            name: "B.swift",
                            lineCoverage: 100.0,
                            coveredLines: 50,
                            executableLines: 50,
                        ),
                    ],
                ),
            ],
        )

        let output = GetCoverageReportTool.formatReport(report, showFiles: true)
        #expect(output.contains("A.swift"))
        #expect(output.contains("B.swift"))
        // A.swift (60%) should be listed before B.swift (100%) — weakest first
        let aIndex = try #require(output.range(of: "A.swift")?.lowerBound)
        let bIndex = try #require(output.range(of: "B.swift")?.lowerBound)
        #expect(aIndex < bIndex)
    }

    @Test
    func `Format report without show_files omits file breakdown`() {
        let report = CoverageReport(
            lineCoverage: 80.0,
            coveredLines: 80,
            executableLines: 100,
            targets: [
                TargetCoverage(
                    name: "MyTarget",
                    lineCoverage: 80.0,
                    coveredLines: 80,
                    executableLines: 100,
                    files: [
                        FileCoverage(
                            path: "/path/to/A.swift",
                            name: "A.swift",
                            lineCoverage: 100.0,
                            coveredLines: 50,
                            executableLines: 50,
                        ),
                    ],
                ),
            ],
        )

        let output = GetCoverageReportTool.formatReport(report, showFiles: false)
        #expect(output.contains("MyTarget"))
        #expect(!output.contains("A.swift"))
    }

    @Test
    func `Execute with non-existent bundle path throws`() async {
        let tool = GetCoverageReportTool()
        do {
            _ = try await tool.execute(arguments: [
                "result_bundle_path": .string("/nonexistent/path.xcresult"),
            ])
            Issue.record("Expected MCPError to be thrown")
        } catch {
            #expect(String(describing: error).contains("not found"))
        }
    }

    @Test
    func `Execute with missing required param throws`() async {
        let tool = GetCoverageReportTool()
        do {
            _ = try await tool.execute(arguments: [:])
            Issue.record("Expected MCPError to be thrown")
        } catch {
            #expect(String(describing: error).contains("required"))
        }
    }
}
