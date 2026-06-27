import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
@testable import XCMCPTools

struct SetSchemeStoreKitConfigToolTests {
    /// A realistic shared scheme with both a `TestAction` and a `LaunchAction`, Xcode-formatted.
    private static let schemeXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme
       LastUpgradeVersion = "2600"
       version = "1.7">
       <BuildAction
          parallelizeBuildables = "YES"
          buildImplicitDependencies = "YES">
       </BuildAction>
       <TestAction
          buildConfiguration = "Debug"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          shouldUseLaunchSchemeArgsEnv = "YES">
          <TestPlans>
             <TestPlanReference
                reference = "container:UnitTests.xctestplan"
                default = "YES">
             </TestPlanReference>
          </TestPlans>
       </TestAction>
       <LaunchAction
          buildConfiguration = "Debug"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          launchStyle = "0"
          useCustomWorkingDirectory = "NO"
          ignoresPersistentStateOnLaunch = "NO"
          debugDocumentVersioning = "YES"
          debugServiceExtension = "internal"
          allowLocationSimulation = "YES">
          <BuildableProductRunnable
             runnableDebuggingMode = "0">
          </BuildableProductRunnable>
       </LaunchAction>
    </Scheme>

    """

    /// Creates a temp project directory containing the scheme and a repo-root `.storekit` file.
    /// Returns (basePath, projectPath, schemePath, storekitPath).
    private static func makeFixture(
        storekitName: String = "Config.storekit",
    ) throws -> (base: String, project: String, scheme: String, storekit: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let projectPath = tempDir.appendingPathComponent("TestProject.xcodeproj")
        let schemesDir = projectPath.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemesDir, withIntermediateDirectories: true)

        let schemePath = schemesDir.appendingPathComponent("App.xcscheme")
        try schemeXML.write(to: schemePath, atomically: true, encoding: .utf8)

        let storekitPath = tempDir.appendingPathComponent(storekitName)
        try "{}".write(to: storekitPath, atomically: true, encoding: .utf8)

        return (tempDir.path, projectPath.path, schemePath.path, storekitPath.path)
    }

    private func runTool(
        base: String,
        arguments: [String: Value],
    ) throws -> String {
        let tool = SetSchemeStoreKitConfigTool(pathUtility: PathUtility(basePath: base))
        let result = try tool.execute(arguments: arguments)
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return ""
        }
        return message
    }

    @Test
    func `Tool creation`() {
        let tool = SetSchemeStoreKitConfigTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "set_scheme_storekit_config")
    }

    @Test
    func `Add to both actions computes scheme-relative identifier`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try runTool(base: fixture.base, arguments: [
            "project_path": .string(fixture.project),
            "scheme_name": .string("App"),
            "storekit_path": .string(fixture.storekit),
        ])
        #expect(message.contains("../../../Config.storekit"))

        let written = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        let refCount = written.components(
            separatedBy: "<StoreKitConfigurationFileReference",
        ).count - 1
        #expect(refCount == 2, "Expected a reference under both actions, got \(refCount)")
        #expect(written.contains("identifier = \"../../../Config.storekit\""))

        // The reference must sit inside each action block (before its closing tag).
        let testBlock = try #require(Self.actionBlock("TestAction", in: written))
        #expect(testBlock.contains("StoreKitConfigurationFileReference"))
        let launchBlock = try #require(Self.actionBlock("LaunchAction", in: written))
        #expect(launchBlock.contains("StoreKitConfigurationFileReference"))
    }

    @Test
    func `Add is idempotent`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let args: [String: Value] = [
            "project_path": .string(fixture.project),
            "scheme_name": .string("App"),
            "storekit_path": .string(fixture.storekit),
        ]
        _ = try runTool(base: fixture.base, arguments: args)
        _ = try runTool(base: fixture.base, arguments: args)

        let written = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        let refCount = written.components(
            separatedBy: "<StoreKitConfigurationFileReference",
        ).count - 1
        #expect(refCount == 2, "Repeat calls must not duplicate references, got \(refCount)")
    }

    @Test
    func `Add to launch only preserves an existing test reference`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        // Seed both actions, then re-target only launch with a different config.
        _ = try runTool(base: fixture.base, arguments: [
            "project_path": .string(fixture.project),
            "scheme_name": .string("App"),
            "storekit_path": .string(fixture.storekit),
        ])

        let otherStorekit = (fixture.base as NSString)
            .appendingPathComponent("Other.storekit")
        try "{}".write(toFile: otherStorekit, atomically: true, encoding: .utf8)

        _ = try runTool(base: fixture.base, arguments: [
            "project_path": .string(fixture.project),
            "scheme_name": .string("App"),
            "storekit_path": .string(otherStorekit),
            "target_actions": .string("launch"),
        ])

        let written = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        let testBlock = try #require(Self.actionBlock("TestAction", in: written))
        let launchBlock = try #require(Self.actionBlock("LaunchAction", in: written))
        #expect(testBlock.contains("../../../Config.storekit"))
        #expect(launchBlock.contains("../../../Other.storekit"))
        #expect(!launchBlock.contains("Config.storekit"))
    }

    @Test
    func `Remove clears references from both actions`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        _ = try runTool(base: fixture.base, arguments: [
            "project_path": .string(fixture.project),
            "scheme_name": .string("App"),
            "storekit_path": .string(fixture.storekit),
        ])

        let message = try runTool(base: fixture.base, arguments: [
            "project_path": .string(fixture.project),
            "scheme_name": .string("App"),
            "action": .string("remove"),
        ])
        #expect(message.contains("Removed"))

        let written = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        #expect(!written.contains("StoreKitConfigurationFileReference"))
        // The rest of the scheme is intact.
        #expect(written.contains("<TestPlans>"))
        #expect(written.contains("<BuildableProductRunnable"))
    }

    @Test
    func `Remove when no reference present reports nothing to do`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try runTool(base: fixture.base, arguments: [
            "project_path": .string(fixture.project),
            "scheme_name": .string("App"),
            "action": .string("remove"),
        ])
        #expect(message.contains("No StoreKit reference"))
    }

    @Test
    func `Add without storekit_path throws`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let tool = SetSchemeStoreKitConfigTool(pathUtility: PathUtility(basePath: fixture.base))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(fixture.project),
                "scheme_name": .string("App"),
            ])
        }
    }

    @Test
    func `Missing scheme reports not found`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try runTool(base: fixture.base, arguments: [
            "project_path": .string(fixture.project),
            "scheme_name": .string("DoesNotExist"),
            "storekit_path": .string(fixture.storekit),
        ])
        #expect(message.contains("not found"))
    }

    /// Returns the substring of `content` spanning `<Name …>` … `</Name>`.
    private static func actionBlock(_ name: String, in content: String) -> String? {
        guard let open = content.range(of: "<\(name)"),
              let close = content.range(
                  of: "</\(name)>", range: open.upperBound ..< content.endIndex,
              )
        else { return nil }
        return String(content[open.lowerBound ..< close.upperBound])
    }
}
