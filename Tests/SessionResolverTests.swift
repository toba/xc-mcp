import MCP
import Testing
import Foundation
@testable import XCMCPCore

/// Covers the resolvers that tool code calls in place of reading a session property directly.
@Suite(.temporaryDirectory, .serialized)
struct SessionResolverTests {
    private func makeManager() -> SessionManager {
        .init(
            filePath: TemporaryDirectory.url.appendingPathComponent("xc-mcp-test.json"),
            enableWarmup: false,
        )
    }

    // MARK: - resolveOptionalSimulator

    @Test
    func `resolveOptionalSimulator prefers the argument over the session default`() async {
        let manager = makeManager()
        await manager.setDefaults(simulatorUDID: "SESSION-UDID")

        let resolved = await manager.resolveOptionalSimulator(from: [
            "simulator": .string("ARG-UDID")
        ])
        #expect(resolved == "ARG-UDID")
    }

    @Test
    func `resolveOptionalSimulator falls back to the session default`() async {
        let manager = makeManager()
        await manager.setDefaults(simulatorUDID: "SESSION-UDID")

        let resolved = await manager.resolveOptionalSimulator(from: [:])
        #expect(resolved == "SESSION-UDID")
    }

    @Test
    func `resolveOptionalSimulator returns nil when neither source supplies one`() async {
        let manager = makeManager()

        let resolved = await manager.resolveOptionalSimulator(from: [:])
        #expect(resolved == nil)
    }

    // MARK: - resolvePackagePath

    @Test
    func `resolvePackagePath rejects a directory that holds no Package swift`() async throws {
        let manager = makeManager()
        let empty = TemporaryDirectory.url.appendingPathComponent("no-package", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        await #expect(throws: MCPError.self) {
            try await manager.resolvePackagePath(from: ["package_path": .string(empty.path)])
        }
    }

    @Test
    func `resolvePackagePath accepts a directory that holds a Package swift`() async throws {
        let manager = makeManager()
        let root = TemporaryDirectory.url.appendingPathComponent("a-package", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.4\n".write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8,
        )

        let resolved = try await manager.resolvePackagePath(from: [
            "package_path": .string(root.path)
        ])
        #expect(resolved == PathUtility.resolvePath(from: root.path))
    }

    // MARK: - resolveSourceRoot

    @Test
    func `resolveSourceRoot accepts a directory that holds no Package swift`() async throws {
        let manager = makeManager()
        let loose = TemporaryDirectory.url.appendingPathComponent("loose", isDirectory: true)
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)

        let resolved = try await manager.resolveSourceRoot(from: [
            "package_path": .string(loose.path)
        ])
        #expect(resolved == PathUtility.resolvePath(from: loose.path))
    }

    @Test
    func `resolveSourceRoot rejects a path that names no directory`() async throws {
        let manager = makeManager()
        let missing = TemporaryDirectory.url.appendingPathComponent("gone", isDirectory: true)

        await #expect(throws: MCPError.self) {
            try await manager.resolveSourceRoot(from: ["package_path": .string(missing.path)])
        }
    }

    @Test
    func `resolveSourceRoot rejects a path that names a file`() async throws {
        let manager = makeManager()
        let file = TemporaryDirectory.url.appendingPathComponent("Lone.swift")
        try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)

        await #expect(throws: MCPError.self) {
            try await manager.resolveSourceRoot(from: ["package_path": .string(file.path)])
        }
    }
}
