import MCP
import Testing
@testable import XCMCPCore
import Foundation
import Subprocess

@Suite("SessionManager Persistence", .serialized)
struct SessionManagerPersistenceTests {
    /// Clean up the shared file before and after each test.
    private func cleanup() {
        try? FileManager.default.removeItem(at: SessionManager.sharedFilePath)
    }

    @Test("Defaults persist to disk and load in new instance")
    func roundTrip() async {
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

    @Test("All fields persist correctly")
    func allFields() async {
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

    @Test("Clear deletes shared file")
    func clearDeletesFile() async {
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

    @Test("Corrupted file is ignored gracefully")
    func corruptedFile() async throws {
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

    @Test("setDefaults merges and persists incrementally")
    func incrementalMerge() async {
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

    @Test("Running instance reloads when another process writes the shared file")
    func crossProcessReload() async {
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

    @Test("resolveScheme picks up externally written defaults")
    func resolveAfterExternalWrite() async throws {
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

    @Test("Env vars persist to disk and reload")
    func envPersistence() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["FOO": "bar", "BAZ": "qux"])

        let manager2 = SessionManager()
        let defaults = await manager2.getDefaults()
        #expect(defaults.env == ["FOO": "bar", "BAZ": "qux"])
    }

    @Test("Env deep-merge adds new keys and updates existing")
    func envDeepMerge() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["A": "1", "B": "2"])
        await manager.setDefaults(env: ["B": "updated", "C": "3"])

        let defaults = await manager.getDefaults()
        #expect(defaults.env == ["A": "1", "B": "updated", "C": "3"])
    }

    @Test("Clear resets env to nil")
    func clearResetsEnv() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["KEY": "value"])
        await manager.clear()

        let defaults = await manager.getDefaults()
        #expect(defaults.env == nil)
    }

    @Test("resolveEnvironment merges session and per-invocation env")
    func resolveEnvironmentMerge() async {
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

    @Test("resolveEnvironment returns inherit when no env configured")
    func resolveEnvironmentEmpty() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        let environment = await manager.resolveEnvironment(from: [:])
        #expect(environment == .inherit)
    }

    @Test("Summary includes env vars")
    func summaryIncludesEnv() async {
        cleanup()
        defer { cleanup() }

        let manager = SessionManager()
        await manager.setDefaults(env: ["DYLD_PRINT_LIBRARIES": "1"])

        let summary = await manager.summary()
        #expect(summary.contains("DYLD_PRINT_LIBRARIES=1"))
    }
}
