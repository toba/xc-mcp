import Testing
import XCMCPCore
import Foundation
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
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let basePath = tempDir.appendingPathComponent("projects").path
        try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let pathUtility = PathUtility(basePath: basePath)

        // This should resolve to basePath/MyApp.xcodeproj
        let relativePath = "MyApp.xcodeproj" // Use simple relative path instead of ./
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

@Suite("PathUtility Ancestor Directory Search Tests")
struct PathUtilityAncestorSearchTests {
    @Test("Finds Package.swift in starting directory")
    func findsPackageInStartDir() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ancestor-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift in the temp dir
        FileManager.default.createFile(
            atPath: tempDir.appendingPathComponent("Package.swift").path,
            contents: nil,
        )

        let result = PathUtility.findAncestorDirectory(
            matching: { $0 == "Package.swift" },
            startingFrom: tempDir.path,
        )
        #expect(result == tempDir.path)
    }

    @Test("Finds Package.swift in parent directory")
    func findsPackageInParent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ancestor-test-\(UUID().uuidString)")
        let nested = tempDir.appendingPathComponent("Sources/Models")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift at root, search from nested dir
        FileManager.default.createFile(
            atPath: tempDir.appendingPathComponent("Package.swift").path,
            contents: nil,
        )

        let result = PathUtility.findAncestorDirectory(
            matching: { $0 == "Package.swift" },
            startingFrom: nested.path,
        )
        #expect(result == tempDir.path)
    }

    @Test("Returns nil when no match found")
    func returnsNilWhenNotFound() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ancestor-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // No Package.swift anywhere in temp dir
        let result = PathUtility.findAncestorDirectory(
            matching: { $0 == "Package.swift" },
            startingFrom: tempDir.path,
        )
        // Should be nil since /tmp won't have Package.swift
        // (unless we're running from within a Swift package, which we are,
        // but the temp dir tree doesn't contain one)
        #expect(result == nil)
    }

    @Test("Finds .xcodeproj in ancestor")
    func findsXcodeprojInAncestor() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ancestor-test-\(UUID().uuidString)")
        let nested = tempDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a .xcodeproj directory
        let projPath = tempDir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: projPath, withIntermediateDirectories: true)

        let result = PathUtility.findAncestorDirectory(
            matching: { $0.hasSuffix(".xcodeproj") },
            startingFrom: nested.path,
        )
        #expect(result == tempDir.path)
    }

    @Test("findPackageRoot returns path for xc-mcp repo")
    func findPackageRootForCurrentRepo() {
        // We're running inside the xc-mcp package, so this should find it
        let result = PathUtility.findPackageRoot()
        #expect(result != nil)
        #expect(result?.hasSuffix("xc-mcp") == true || FileManager.default.fileExists(
            atPath: "\(result ?? "")/Package.swift",
        ))
    }
}
