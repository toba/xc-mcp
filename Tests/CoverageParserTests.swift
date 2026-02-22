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
    func parseXcodebuildCoverageFormat() throws {
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
        let coverage = parser.parseCoverageFromPath(testFile.path)

        #expect(coverage != nil)
        #expect(coverage?.files.count == 2)
        #expect(abs((coverage?.lineCoverage ?? 0) - 85.0) < 0.1)
    }

    @Test("Parse SPM coverage JSON format")
    func parseSPMCoverageFormat() throws {
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
        let coverage = parser.parseCoverageFromPath(testFile.path)

        #expect(coverage != nil)
        #expect(coverage?.files.count == 2)
        #expect(abs((coverage?.lineCoverage ?? 0) - 85.0) < 0.1)
    }

    @Test("Invalid JSON returns nil")
    func invalidJSONReturnsNil() throws {
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
        let coverage = parser.parseCoverageFromPath(testFile.path)
        #expect(coverage == nil)
    }

    @Test("Empty files array returns nil")
    func emptyFilesArrayReturnsNil() throws {
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
        let coverage = parser.parseCoverageFromPath(testFile.path)
        #expect(coverage == nil)
    }

    @Test("Coverage target filtering")
    func coverageTargetFiltering() throws {
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
        let coverage = parser.parseCoverageFromPath(testFile.path, targetFilter: "MyApp")

        #expect(coverage != nil)
        #expect(coverage?.files.count == 1)
        #expect(coverage?.files.first?.name == "MyFile.swift")
        #expect(abs((coverage?.lineCoverage ?? 0) - 85.0) < 0.1)
    }

    @Test("Coverage excludes test bundles")
    func coverageExcludesTestBundles() throws {
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
        let coverage = parser.parseCoverageFromPath(testFile.path, targetFilter: "MyModule")

        #expect(coverage != nil)
        #expect(coverage?.files.count == 1)
        #expect(coverage?.files.first?.name == "MyFile.swift")
        #expect(abs((coverage?.lineCoverage ?? 0) - 50.0) < 0.1)
    }

    @Test("Non-existent path returns nil")
    func nonExistentPathReturnsNil() {
        let parser = CoverageParser()
        let coverage = parser.parseCoverageFromPath("/nonexistent/path/to/coverage.json")
        #expect(coverage == nil)
    }
}
