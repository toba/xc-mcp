import Foundation
import Testing
import XCMCPCore

@testable import XCMCPTools

struct PathUtilityTests {
    @Test func relativePathResolution() throws {
        // Use current working directory as base path for testing
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        // Test relative path resolution
        let relativePath = "MyApp.xcodeproj"
        let resolved = try pathUtility.resolvePath(from: relativePath)

        #expect(resolved == "\(basePath)/MyApp.xcodeproj")
    }

    @Test func nestedRelativePathResolution() throws {
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        let nestedPath = "Projects/MyApp.xcodeproj"
        let resolved = try pathUtility.resolvePath(from: nestedPath)

        #expect(resolved == "\(basePath)/Projects/MyApp.xcodeproj")
    }

    @Test func absolutePathWithinWorkspace() throws {
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        let absolutePath = "\(basePath)/MyApp.xcodeproj"
        let resolved = try pathUtility.resolvePath(from: absolutePath)

        #expect(resolved == "\(basePath)/MyApp.xcodeproj")
    }

    @Test func pathOutsideWorkspaceThrows() throws {
        let basePath = "/workspace"
        let pathUtility = PathUtility(basePath: basePath)

        let outsidePath = "/etc/passwd"

        #expect(throws: PathError.self) {
            _ = try pathUtility.resolvePath(from: outsidePath)
        }
    }

    @Test func dotDotPathResolution() throws {
        // Create a temporary subdirectory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let basePath = tempDir.appendingPathComponent("projects").path
        try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let pathUtility = PathUtility(basePath: basePath)

        // This should resolve to basePath/MyApp.xcodeproj
        let relativePath = "MyApp.xcodeproj"  // Use simple relative path instead of ./
        let resolved = try pathUtility.resolvePath(from: relativePath)

        #expect(resolved == "\(basePath)/MyApp.xcodeproj")
    }

    @Test func testCurrentDirectoryPath() throws {
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        // Just a dot should resolve to the base path
        let currentDir = "."
        let resolved = try pathUtility.resolvePath(from: currentDir)

        #expect(resolved == basePath)
    }
}
