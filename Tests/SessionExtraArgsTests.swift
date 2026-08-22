import MCP
import Testing
import Foundation
@testable import XCMCPCore

@Suite(.temporaryDirectory, .serialized)
struct SessionExtraArgsTests {
    private func makeTempPath() -> URL {
        TemporaryDirectory.url.appendingPathComponent("xc-mcp-test.json")
    }

    private func makeManager(_ path: URL) -> SessionManager {
        .init(filePath: path, enableWarmup: false)
    }

    // MARK: - Persistence

    @Test
    func `extraArgs persist to disk and load in a new instance`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(extraArgs: ["-skipPackagePluginValidation", "-quiet"])

        let reloaded = makeManager(path)
        let defaults = await reloaded.getDefaults()
        #expect(defaults.extraArgs == ["-skipPackagePluginValidation", "-quiet"])
    }

    @Test
    func `Empty extraArgs array clears the persisted list`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(extraArgs: ["-quiet"])
        await manager.setDefaults(extraArgs: [])

        let defaults = await manager.getDefaults()
        #expect(defaults.extraArgs == nil)
    }

    @Test
    func `Setting other defaults leaves extraArgs untouched`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(extraArgs: ["-quiet"])
        await manager.setDefaults(scheme: "MyScheme")

        let defaults = await manager.getDefaults()
        #expect(defaults.extraArgs == ["-quiet"])
        #expect(defaults.scheme == "MyScheme")
    }

    @Test
    func `clear removes extraArgs`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(extraArgs: ["-quiet"])
        await manager.clear()

        let defaults = await manager.getDefaults()
        #expect(defaults.extraArgs == nil)
    }

    // MARK: - Resolution

    @Test
    func `resolveExtraArgs falls back to the session default when the key is absent`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(extraArgs: ["-quiet"])

        let resolved = await manager.resolveExtraArgs(from: [:])
        #expect(resolved == ["-quiet"])
    }

    @Test
    func `Per-invocation extra_args replaces the session default`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(extraArgs: ["-quiet"])

        let args: [String: Value] = ["extra_args": .array([.string("-verbose")])]
        let resolved = await manager.resolveExtraArgs(from: args)
        // Replace, not append: the session "-quiet" is dropped for this call.
        #expect(resolved == ["-verbose"])
    }

    @Test
    func `Empty per-invocation extra_args suppresses the session default for one call`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        await manager.setDefaults(extraArgs: ["-quiet"])

        let args: [String: Value] = ["extra_args": .array([])]
        let resolved = await manager.resolveExtraArgs(from: args)
        #expect(resolved.isEmpty)

        // The persisted session default is untouched by a per-call override.
        let afterwards = await manager.resolveExtraArgs(from: [:])
        #expect(afterwards == ["-quiet"])
    }

    @Test
    func `resolveExtraArgs returns empty when nothing is configured`() async {
        let path = makeTempPath()

        let manager = makeManager(path)
        let resolved = await manager.resolveExtraArgs(from: [:])
        #expect(resolved.isEmpty)
    }
}
