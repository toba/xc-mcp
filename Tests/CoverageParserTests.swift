import Testing
@testable import XCMCPCore
import Foundation

@Suite("CoverageParser Tests")
struct CoverageParserTests {
    @Test("Coverage data structures")
    func codeCoverageDataStructures() {
        let fileCoverage = FileCoverage(
            path: "/path/to/file.swift",
            name: "file.swift",
            lineCoverage: 85.5,
            coveredLines: 50,
            executableLines: 58,
        )

        let coverage = CodeCoverage(
            lineCoverage: 75.0,
            files: [fileCoverage],
        )

        #expect(coverage.lineCoverage == 75.0)
        #expect(coverage.files.count == 1)
        #expect(coverage.files[0].name == "file.swift")
        #expect(coverage.files[0].lineCoverage == 85.5)
    }

    @Test("Parse xcodebuild coverage JSON format")
    func parseXcodebuildCoverageFormat() async throws {
        let xcodebuildJSON = """
        {
          "targets": [{
            "name": "MyTarget",
            "files": [
              {
                "path": "/path/to/main.swift",
                "lineCoverage": 0.90,
                "coveredLines": 45,
                "executableLines": 50
              },
              {
                "path": "/path/to/helper.swift",
                "lineCoverage": 0.80,
                "coveredLines": 40,
                "executableLines": 50
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent(
            "xcodebuild-coverage-\(UUID().uuidString).json",
        )
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let parser = CoverageParser()
        let coverage = await parser.parseCoverageFromPath(testFile.path)

        #expect(coverage != nil)
        #expect(coverage?.files.count == 2)
        #expect(abs((coverage?.lineCoverage ?? 0) - 85.0) < 0.1)
    }

    @Test("Parse SPM coverage JSON format")
    func parseSPMCoverageFormat() async throws {
        let spmJSON = """
        {
          "data": [{
            "files": [
              {
                "filename": "/path/to/main.swift",
                "summary": {
                  "lines": {
                    "covered": 45,
                    "count": 50
                  }
                }
              },
              {
                "filename": "/path/to/helper.swift",
                "summary": {
                  "lines": {
                    "covered": 40,
                    "count": 50
                  }
                }
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("spm-coverage-\(UUID().uuidString).json")
        try spmJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let parser = CoverageParser()
        let coverage = await parser.parseCoverageFromPath(testFile.path)

        #expect(coverage != nil)
        #expect(coverage?.files.count == 2)
        #expect(abs((coverage?.lineCoverage ?? 0) - 85.0) < 0.1)
    }

    @Test("Invalid JSON returns nil")
    func invalidJSONReturnsNil() async throws {
        let invalidJSON = """
        {
          "invalid": "format"
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("invalid-coverage-\(UUID().uuidString).json")
        try invalidJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let parser = CoverageParser()
        let coverage = await parser.parseCoverageFromPath(testFile.path)
        #expect(coverage == nil)
    }

    @Test("Empty files array returns nil")
    func emptyFilesArrayReturnsNil() async throws {
        let emptyJSON = """
        {
          "data": [{
            "files": []
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("empty-coverage-\(UUID().uuidString).json")
        try emptyJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let parser = CoverageParser()
        let coverage = await parser.parseCoverageFromPath(testFile.path)
        #expect(coverage == nil)
    }

    @Test("Coverage target filtering")
    func coverageTargetFiltering() async throws {
        let xcodebuildJSON = """
        {
          "targets": [
            {
              "name": "MyApp.app",
              "files": [
                {
                  "path": "/path/to/MyFile.swift",
                  "lineCoverage": 0.85,
                  "coveredLines": 85,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "OtherApp.app",
              "files": [
                {
                  "path": "/path/to/OtherFile.swift",
                  "lineCoverage": 0.50,
                  "coveredLines": 50,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("filtered-coverage-\(UUID().uuidString).json")
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let parser = CoverageParser()
        let coverage = await parser.parseCoverageFromPath(testFile.path, targetFilter: "MyApp")

        #expect(coverage != nil)
        #expect(coverage?.files.count == 1)
        #expect(coverage?.files.first?.name == "MyFile.swift")
        #expect(abs((coverage?.lineCoverage ?? 0) - 85.0) < 0.1)
    }

    @Test("Coverage excludes test bundles")
    func coverageExcludesTestBundles() async throws {
        let xcodebuildJSON = """
        {
          "targets": [
            {
              "name": "MyModule.framework",
              "files": [
                {
                  "path": "/path/to/MyFile.swift",
                  "lineCoverage": 0.50,
                  "coveredLines": 50,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "MyModuleTests.xctest",
              "files": [
                {
                  "path": "/path/to/MyModuleTests.swift",
                  "lineCoverage": 1.0,
                  "coveredLines": 100,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent(
            "exclude-tests-coverage-\(UUID().uuidString).json",
        )
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let parser = CoverageParser()
        let coverage = await parser.parseCoverageFromPath(testFile.path, targetFilter: "MyModule")

        #expect(coverage != nil)
        #expect(coverage?.files.count == 1)
        #expect(coverage?.files.first?.name == "MyFile.swift")
        #expect(abs((coverage?.lineCoverage ?? 0) - 50.0) < 0.1)
    }

    @Test("Non-existent path returns nil")
    func nonExistentPathReturnsNil() async {
        let parser = CoverageParser()
        let coverage = await parser.parseCoverageFromPath("/nonexistent/path/to/coverage.json")
        #expect(coverage == nil)
    }

    // MARK: - Target-Level Coverage Report

    @Test("Parse target coverage from xcodebuild JSON")
    func parseTargetCoverage() throws {
        let json: [String: Any] = [
            "targets": [
                [
                    "name": "MyApp.app",
                    "lineCoverage": 0.85,
                    "files": [
                        [
                            "path": "/path/to/A.swift",
                            "lineCoverage": 0.90,
                            "coveredLines": 45,
                            "executableLines": 50,
                        ],
                        [
                            "path": "/path/to/B.swift",
                            "lineCoverage": 0.80,
                            "coveredLines": 40,
                            "executableLines": 50,
                        ],
                    ],
                ],
                [
                    "name": "MyFramework.framework",
                    "files": [
                        [
                            "path": "/path/to/C.swift",
                            "lineCoverage": 0.50,
                            "coveredLines": 25,
                            "executableLines": 50,
                        ],
                    ],
                ],
                [
                    "name": "MyTests.xctest",
                    "files": [
                        [
                            "path": "/path/to/Tests.swift",
                            "lineCoverage": 1.0,
                            "coveredLines": 100,
                            "executableLines": 100,
                        ],
                    ],
                ],
            ],
        ]

        let report = CoverageParser.parseTargetCoverage(json: json)
        #expect(report != nil)
        #expect(report?.targets.count == 2) // xctest excluded
        #expect(report?.coveredLines == 110)
        #expect(report?.executableLines == 150)

        let app = try #require(report?.targets.first { $0.name == "MyApp.app" })
        #expect(app.files.count == 2)
        #expect(app.coveredLines == 85)
    }

    @Test("Parse target coverage with filter")
    func parseTargetCoverageWithFilter() {
        let json: [String: Any] = [
            "targets": [
                [
                    "name": "MyApp.app",
                    "files": [
                        [
                            "path": "/a.swift",
                            "lineCoverage": 0.90,
                            "coveredLines": 45,
                            "executableLines": 50,
                        ],
                    ],
                ],
                [
                    "name": "OtherLib.framework",
                    "files": [
                        [
                            "path": "/b.swift",
                            "lineCoverage": 0.50,
                            "coveredLines": 25,
                            "executableLines": 50,
                        ],
                    ],
                ],
            ],
        ]

        let report = CoverageParser.parseTargetCoverage(json: json, targetFilter: "myapp")
        #expect(report != nil)
        #expect(report?.targets.count == 1)
        #expect(report?.targets[0].name == "MyApp.app")
    }

    @Test("Parse target coverage returns nil for empty targets")
    func parseTargetCoverageEmpty() {
        let json: [String: Any] = ["targets": [] as [[String: Any]]]
        let report = CoverageParser.parseTargetCoverage(json: json)
        #expect(report == nil)
    }

    // MARK: - Function-Level Coverage

    @Test("Parse function coverage JSON array format")
    func parseFunctionCoverageArray() throws {
        let json = """
        [
          {
            "name": "init()",
            "lineNumber": 10,
            "coveredLines": 5,
            "executableLines": 5,
            "lineCoverage": 1.0,
            "executionCount": 3
          },
          {
            "name": "doWork()",
            "lineNumber": 20,
            "coveredLines": 0,
            "executableLines": 8,
            "lineCoverage": 0.0,
            "executionCount": 0
          }
        ]
        """

        let data = try #require(json.data(using: .utf8))
        let result = CoverageParser.parseFunctionCoverageJSON(
            jsonData: data, filePath: "/path/to/File.swift",
        )

        #expect(result != nil)
        #expect(result?.functions.count == 2)
        #expect(result?.coveredLines == 5)
        #expect(result?.executableLines == 13)
        #expect(result?.functions[0].name == "init()")
        #expect(result?.functions[0].executionCount == 3)
        #expect(result?.functions[1].executionCount == 0)
    }

    @Test("Parse function coverage empty array returns nil")
    func parseFunctionCoverageEmpty() {
        let data = Data("[]".utf8)
        let result = CoverageParser.parseFunctionCoverageJSON(
            jsonData: data, filePath: "/path/to/File.swift",
        )
        #expect(result == nil)
    }

    // MARK: - Uncovered Line Ranges

    @Test("Parse uncovered lines from archive output")
    func parseUncoveredLines() {
        let archiveOutput = """
           1: *
           2: 1
           3: 0
           4: 0
           5: 1
           6: 1
           7: 0
           8: *
        """

        let ranges = CoverageParser.parseUncoveredLinesFromArchive(archiveOutput)

        #expect(ranges.count == 2)
        #expect(ranges[0].start == 3)
        #expect(ranges[0].end == 4)
        #expect(ranges[1].start == 7)
        #expect(ranges[1].end == 7)
    }

    @Test("Parse uncovered lines trailing range")
    func parseUncoveredLinesTrailing() {
        let archiveOutput = """
           1: 1
           2: 0
           3: 0
        """

        let ranges = CoverageParser.parseUncoveredLinesFromArchive(archiveOutput)
        #expect(ranges.count == 1)
        #expect(ranges[0].start == 2)
        #expect(ranges[0].end == 3)
    }

    @Test("Parse uncovered lines empty output")
    func parseUncoveredLinesEmpty() {
        let ranges = CoverageParser.parseUncoveredLinesFromArchive("")
        #expect(ranges.isEmpty)
    }

    @Test("Parse uncovered lines all covered")
    func parseUncoveredLinesAllCovered() {
        let archiveOutput = """
           1: 1
           2: 3
           3: *
        """

        let ranges = CoverageParser.parseUncoveredLinesFromArchive(archiveOutput)
        #expect(ranges.isEmpty)
    }
}
