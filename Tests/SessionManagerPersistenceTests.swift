import MCP
import Testing
@testable import XCMCPCore
import Foundation
import Subprocess

@Suite(.serialized)
struct SessionManagerPersistenceTests {
    /// Clean up the shared file before and after each test.
    private func cleanup() {
        try? FileManager.default.removeItem(at: SessionManager.sharedFilePath)
    }

    @Test
    func `Defaults persist to disk and load in new instance`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(
            projectPath: "/path/to/Project.xcodeproj",
            scheme: "MyScheme",
            configuration: "Release",
        )

        // New instance should pick up persisted defaults
        let manager2 = SessionManager()
        let defaults = await manager2.getDefaults()
        #expect(defaults.projectPath == "/path/to/Project.xcodeproj")
        #expect(defaults.scheme == "MyScheme")
        #expect(defaults.configuration == "Release")
        #expect(defaults.workspacePath == nil)
    }

    @Test
    func `All fields persist correctly`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(
            workspacePath: "/path/to/App.xcworkspace",
            packagePath: "/path/to/package",
            scheme: "AppScheme",
            simulatorUDID: "AAAA-BBBB-CCCC",
            deviceUDID: "DDDD-EEEE-FFFF",
            configuration: "Debug",
        )

        let manager2 = SessionManager()
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
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(scheme: "TestScheme")
        #expect(FileManager.default.fileExists(atPath: SessionManager.sharedFilePath.path))

        await manager.clear()
        #expect(!FileManager.default.fileExists(atPath: SessionManager.sharedFilePath.path))

        // New instance should have no defaults
        let manager2 = SessionManager()
        let defaults = await manager2.getDefaults()
        #expect(defaults.scheme == nil)
    }

    @Test
    func `Corrupted file is ignored gracefully`() async throws {
        cleanup()
        defer { cleanup() }

        // Write garbage to the shared file
        try Data("not json".utf8).write(to: SessionManager.sharedFilePath)

        // Should init without crashing, with empty defaults
        let manager = SessionManager()
        let defaults = await manager.getDefaults()
        #expect(defaults.projectPath == nil)
        #expect(defaults.scheme == nil)
    }

    @Test
    func `setDefaults merges and persists incrementally`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(scheme: "First")
        await manager.setDefaults(configuration: "Release")

        let manager2 = SessionManager()
        let defaults = await manager2.getDefaults()
        #expect(defaults.scheme == "First")
        #expect(defaults.configuration == "Release")
    }

    @Test
    func `Running instance reloads when another process writes the shared file`() async {
        cleanup()
        defer { cleanup() }

        // Simulate two long-running servers — both already initialized
        let server1 = SessionManager()
        let server2 = SessionManager()

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
        cleanup()
        defer { cleanup() }

        let server1 = SessionManager()
        let server2 = SessionManager()

        await server1.setDefaults(scheme: "External")

        // server2 should resolve the scheme without needing its own setDefaults
        let scheme = try await server2.resolveScheme(from: [:])
        #expect(scheme == "External")
    }

    // MARK: - Environment Variable Tests

    @Test
    func `Env vars persist to disk and reload`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["FOO": "bar", "BAZ": "qux"])

        let manager2 = SessionManager()
        let defaults = await manager2.getDefaults()
        #expect(defaults.env == ["FOO": "bar", "BAZ": "qux"])
    }

    @Test
    func `Env deep-merge adds new keys and updates existing`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["A": "1", "B": "2"])
        await manager.setDefaults(env: ["B": "updated", "C": "3"])

        let defaults = await manager.getDefaults()
        #expect(defaults.env == ["A": "1", "B": "updated", "C": "3"])
    }

    @Test
    func `Clear resets env to nil`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["KEY": "value"])
        await manager.clear()

        let defaults = await manager.getDefaults()
        #expect(defaults.env == nil)
    }

    @Test
    func `resolveEnvironment merges session and per-invocation env`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
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
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        let environment = await manager.resolveEnvironment(from: [:])
        #expect(environment == .inherit)
    }

    @Test
    func `Summary includes env vars`() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["DYLD_PRINT_LIBRARIES": "1"])

        let summary = await manager.summary()
        #expect(summary.contains("DYLD_PRINT_LIBRARIES=1"))
    }
}
