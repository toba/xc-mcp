import MCP
import Testing
@testable import XCMCPCore
import Foundation
import Subprocess

@Suite(.serialized)
struct SessionManagerPersistenceTests {
    /// Each test gets its own temp file to avoid interference.
    private func makeTempPath() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xc-mcp-test-\(UUID().uuidString).json")
    }

    @Test
    func `Defaults persist to disk and load in new instance`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(
            projectPath: "/path/to/Project.xcodeproj",
            scheme: "MyScheme",
            configuration: "Release",
        )

        // New instance should pick up persisted defaults
        let manager2 = SessionManager(filePath: path)
        let defaults = await manager2.getDefaults()
        #expect(defaults.projectPath == "/path/to/Project.xcodeproj")
        #expect(defaults.scheme == "MyScheme")
        #expect(defaults.configuration == "Release")
        #expect(defaults.workspacePath == nil)
    }

    @Test
    func `All fields persist correctly`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(
            workspacePath: "/path/to/App.xcworkspace",
            packagePath: "/path/to/package",
            scheme: "AppScheme",
            simulatorUDID: "AAAA-BBBB-CCCC",
            deviceUDID: "DDDD-EEEE-FFFF",
            configuration: "Debug",
        )

        let manager2 = SessionManager(filePath: path)
        let defaults = await manager2.getDefaults()
        #expect(defaults.workspacePath == "/path/to/App.xcworkspace")
        #expect(defaults.packagePath == "/path/to/package")
        #expect(defaults.scheme == "AppScheme")
        #expect(defaults.simulatorUDID == "AAAA-BBBB-CCCC")
        #expect(defaults.deviceUDID == "DDDD-EEEE-FFFF")
        #expect(defaults.configuration == "Debug")
    }

    @Test
    func `Clear deletes shared file`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(scheme: "TestScheme")
        #expect(FileManager.default.fileExists(atPath: path.path))

        await manager.clear()
        #expect(!FileManager.default.fileExists(atPath: path.path))

        // New instance should have no defaults
        let manager2 = SessionManager(filePath: path)
        let defaults = await manager2.getDefaults()
        #expect(defaults.scheme == nil)
    }

    @Test
    func `Corrupted file is ignored gracefully`() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        // Write garbage to the file
        try Data("not json".utf8).write(to: path)

        // Should init without crashing, with empty defaults
        let manager = SessionManager(filePath: path)
        let defaults = await manager.getDefaults()
        #expect(defaults.projectPath == nil)
        #expect(defaults.scheme == nil)
    }

    @Test
    func `setDefaults merges and persists incrementally`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(scheme: "First")
        await manager.setDefaults(configuration: "Release")

        let manager2 = SessionManager(filePath: path)
        let defaults = await manager2.getDefaults()
        #expect(defaults.scheme == "First")
        #expect(defaults.configuration == "Release")
    }

    @Test
    func `Running instance reloads when another process writes the shared file`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        // Simulate two long-running servers — both already initialized
        let server1 = SessionManager(filePath: path)
        let server2 = SessionManager(filePath: path)

        // server1 sets defaults (writes shared file)
        await server1.setDefaults(
            projectPath: "/path/to/Project.xcodeproj",
            scheme: "Standard",
        )

        // server2 was already running — should pick up the change on next resolve
        let defaults = await server2.getDefaults()
        #expect(defaults.projectPath == "/path/to/Project.xcodeproj")
        #expect(defaults.scheme == "Standard")
    }

    @Test
    func `resolveScheme picks up externally written defaults`() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let server1 = SessionManager(filePath: path)
        let server2 = SessionManager(filePath: path)

        await server1.setDefaults(scheme: "External")

        // server2 should resolve the scheme without needing its own setDefaults
        let scheme = try await server2.resolveScheme(from: [:])
        #expect(scheme == "External")
    }

    // MARK: - Environment Variable Tests

    @Test
    func `Env vars persist to disk and reload`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(env: ["FOO": "bar", "BAZ": "qux"])

        let manager2 = SessionManager(filePath: path)
        let defaults = await manager2.getDefaults()
        #expect(defaults.env == ["FOO": "bar", "BAZ": "qux"])
    }

    @Test
    func `Env deep-merge adds new keys and updates existing`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(env: ["A": "1", "B": "2"])
        await manager.setDefaults(env: ["B": "updated", "C": "3"])

        let defaults = await manager.getDefaults()
        #expect(defaults.env == ["A": "1", "B": "updated", "C": "3"])
    }

    @Test
    func `Clear resets env to nil`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(env: ["KEY": "value"])
        await manager.clear()

        let defaults = await manager.getDefaults()
        #expect(defaults.env == nil)
    }

    @Test
    func `resolveEnvironment merges session and per-invocation env`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(env: ["SESSION_KEY": "session", "SHARED": "from_session"])

        // Per-invocation env overrides SHARED and adds NEW_KEY
        let arguments: [String: Value] = [
            "env": .object([
                "SHARED": .string("from_invocation"),
                "NEW_KEY": .string("new"),
            ]),
        ]

        let environment = await manager.resolveEnvironment(from: arguments)

        // Verify it's not .inherit (it has overrides)
        #expect(environment != .inherit)
    }

    @Test
    func `resolveEnvironment returns inherit when no env configured`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        let environment = await manager.resolveEnvironment(from: [:])
        #expect(environment == .inherit)
    }

    @Test
    func `Summary includes env vars`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(env: ["DYLD_PRINT_LIBRARIES": "1"])

        let summary = await manager.summary()
        #expect(summary.contains("DYLD_PRINT_LIBRARIES=1"))
    }
}
