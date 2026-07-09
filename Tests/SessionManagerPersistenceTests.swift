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

    // MARK: - Absolute Path Normalization (vqc-o14)

    @Test
    func `Relative project_path is stored as an absolute path`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(projectPath: "Thesis.xcodeproj")

        let defaults = await manager.getDefaults()
        let stored = try! #require(defaults.projectPath)
        #expect(stored.hasPrefix("/"))
        #expect(stored.hasSuffix("Thesis.xcodeproj"))
        // Must not collapse to the cwd's own leaf name (the `jason-<hash>` bug).
        #expect(URL(fileURLWithPath: stored).deletingPathExtension().lastPathComponent == "Thesis")
    }

    @Test
    func `resolveBuildPaths returns a stable absolute path after cwd changes`() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        // Establish a known cwd for the moment the relative default is set.
        let fm = FileManager.default
        let originalCwd = fm.currentDirectoryPath
        let projectDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xc-mcp-proj-\(UUID().uuidString)")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer {
            fm.changeCurrentDirectoryPath(originalCwd)
            try? fm.removeItem(at: projectDir)
        }

        #expect(fm.changeCurrentDirectoryPath(projectDir.path))
        let manager = SessionManager(filePath: path)
        await manager.setDefaults(projectPath: "Thesis.xcodeproj")

        let firstResolved = try await manager.resolveBuildPaths(from: [:])

        // Simulate the cwd drifting (different focused server, later tool call).
        #expect(fm.changeCurrentDirectoryPath(NSTemporaryDirectory()))
        let secondResolved = try await manager.resolveBuildPaths(from: [:])

        // The path resolved at set-time must not move when cwd drifts — this is the bug.
        let firstProject = try #require(firstResolved.project)
        #expect(firstProject.hasPrefix("/"))
        #expect(firstProject.hasSuffix("Thesis.xcodeproj"))
        #expect(firstResolved.project == secondResolved.project)

        // Same logical project ⇒ same scoped DerivedData root across calls ⇒ warm cache reuse.
        let firstScope = DerivedDataScoper.scopedPath(workspacePath: nil, projectPath: firstResolved.project)
        let secondScope = DerivedDataScoper.scopedPath(workspacePath: nil, projectPath: secondResolved.project)
        #expect(firstScope == secondScope)
    }

    // MARK: - Configuration Resolution (honor scheme when unspecified)

    @Test
    func `resolveConfiguration returns nil when no argument and no session default`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        // No `-configuration Debug` may be injected here: nil tells the runner to omit the flag so
        // xcodebuild honors the scheme's own Build/Run action configuration.
        let resolved = await manager.resolveConfiguration(from: [:])
        #expect(resolved == nil)
    }

    @Test
    func `resolveConfiguration prefers the explicit argument`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(configuration: "Release")

        let resolved = await manager.resolveConfiguration(
            from: ["configuration": .string("Beta")],
        )
        #expect(resolved == "Beta")
    }

    @Test
    func `resolveConfiguration falls back to the session default`() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(at: path) }

        let manager = SessionManager(filePath: path)
        await manager.setDefaults(configuration: "Release")

        let resolved = await manager.resolveConfiguration(from: [:])
        #expect(resolved == "Release")
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
