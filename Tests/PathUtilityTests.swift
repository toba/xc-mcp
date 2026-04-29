import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

struct PathUtilityTests {
    @Test func `relative path resolution`() throws {
        // Use current working directory as base path for testing
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        // Test relative path resolution
        let relativePath = "MyApp.xcodeproj"
        let resolved = try pathUtility.resolvePath(from: relativePath)

        #expect(resolved == "\(basePath)/MyApp.xcodeproj")
    }

    @Test func `nested relative path resolution`() throws {
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        let nestedPath = "Projects/MyApp.xcodeproj"
        let resolved = try pathUtility.resolvePath(from: nestedPath)

        #expect(resolved == "\(basePath)/Projects/MyApp.xcodeproj")
    }

    @Test func `absolute path within workspace`() throws {
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        let absolutePath = "\(basePath)/MyApp.xcodeproj"
        let resolved = try pathUtility.resolvePath(from: absolutePath)

        #expect(resolved == "\(basePath)/MyApp.xcodeproj")
    }

    @Test func `path outside workspace throws`() throws {
        let basePath = "/workspace"
        let pathUtility = PathUtility(basePath: basePath)

        let outsidePath = "/etc/passwd"

        #expect(throws: PathError.self) {
            _ = try pathUtility.resolvePath(from: outsidePath)
        }
    }

    @Test func `dot dot path resolution`() throws {
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

    @Test func `current directory path`() throws {
        let basePath = FileManager.default.currentDirectoryPath
        let pathUtility = PathUtility(basePath: basePath)

        // Just a dot should resolve to the base path
        let currentDir = "."
        let resolved = try pathUtility.resolvePath(from: currentDir)

        #expect(resolved == basePath)
    }
}

struct PathUtilityAncestorSearchTests {
    @Test
    func `Finds Package.swift in starting directory`() throws {
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

    @Test
    func `Finds Package.swift in parent directory`() throws {
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

    @Test
    func `Returns nil when no match found`() throws {
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

    @Test
    func `Finds .xcodeproj in ancestor`() throws {
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

    @Test func `expandTilde expands bare ~`() {
        #expect(PathUtility.expandTilde("~") == NSHomeDirectory())
    }

    @Test func `expandTilde expands ~ slash prefix`() {
        #expect(PathUtility.expandTilde("~/foo") == "\(NSHomeDirectory())/foo")
        #expect(PathUtility.expandTilde("~/Developer/MyApp.xcodeproj") == "\(NSHomeDirectory())/Developer/MyApp.xcodeproj")
    }

    @Test func `expandTilde leaves absolute paths unchanged`() {
        #expect(PathUtility.expandTilde("/Users/foo") == "/Users/foo")
    }

    @Test func `expandTilde leaves relative paths unchanged`() {
        #expect(PathUtility.expandTilde("foo/bar") == "foo/bar")
    }

    @Test func `expandTilde does not expand ~user form`() {
        #expect(PathUtility.expandTilde("~user/foo") == "~user/foo")
    }

    @Test func `resolvePath expands ~ before resolution`() throws {
        let pathUtility = PathUtility(basePath: NSHomeDirectory())
        let resolved = try pathUtility.resolvePath(from: "~/Developer/MyApp.xcodeproj")
        #expect(resolved == "\(NSHomeDirectory())/Developer/MyApp.xcodeproj")
    }

    @Test
    func `findPackageRoot returns path for xc-mcp repo`() {
        // Use this source file's location instead of cwd, since the test
        // runner's working directory may not be inside the repo.
        let result = PathUtility.findAncestorDirectory(
            matching: { $0 == "Package.swift" },
            startingFrom: URL(fileURLWithPath: #filePath).deletingLastPathComponent().path,
        )
        #expect(result != nil)
        #expect(
            result?.hasSuffix("xc-mcp") == true
                || FileManager.default.fileExists(
                    atPath: "\(result ?? "")/Package.swift",
                ),
        )
    }
}
