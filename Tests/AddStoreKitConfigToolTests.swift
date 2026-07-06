import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct AddStoreKitConfigToolTests {
    /// A minimal shared scheme with both a `TestAction` and a `LaunchAction`.
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
              shouldUseLaunchSchemeArgsEnv = "YES">
           </TestAction>
           <LaunchAction
              buildConfiguration = "Debug"
              launchStyle = "0">
              <BuildableProductRunnable
                 runnableDebuggingMode = "0">
              </BuildableProductRunnable>
           </LaunchAction>
        </Scheme>

        """

    /// Builds a temp project (app target + a test target) with an `App.xcscheme` and a repo-root
    /// `Config.storekit`. `testTargetType` is applied to the second target.
    private static func makeFixture(
        appTarget: String = "App",
        testTarget: String = "AppTests",
        testTargetType: PBXProductType = .unitTestBundle,
    ) throws -> (base: String, project: String, scheme: String, storekit: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let projectPath = tempDir.appendingPathComponent("TestProject.xcodeproj")
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: appTarget, target2: testTarget,
            at: Path(projectPath.path),
        )

        // Make the second target a test bundle (helper creates both as .application).
        let xcodeproj = try XcodeProj(path: Path(projectPath.path))
        if let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == testTarget }) {
            target.productType = testTargetType
        }
        try xcodeproj.write(path: Path(projectPath.path))

        let schemesDir = projectPath.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemesDir, withIntermediateDirectories: true)
        let schemePath = schemesDir.appendingPathComponent("App.xcscheme")
        try schemeXML.write(to: schemePath, atomically: true, encoding: .utf8)

        let storekitPath = tempDir.appendingPathComponent("Config.storekit")
        try "{}".write(to: storekitPath, atomically: true, encoding: .utf8)

        return (tempDir.path, projectPath.path, schemePath.path, storekitPath.path)
    }

    private func addTool(base: String) -> AddStoreKitConfigTool {
        .init(pathUtility: PathUtility(basePath: base))
    }

    private func runAdd(base: String, arguments: [String: Value]) throws -> String {
        let result = try addTool(base: base).execute(arguments: arguments)
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return ""
        }
        return message
    }

    @Test
    func `Tool creation`() {
        let tool = AddStoreKitConfigTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(tool.tool().name == "add_storekit_config")
    }

    @Test
    func `Coherent add wires file reference, test target, and scheme`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try runAdd(
            base: fixture.base,
            arguments: [
                "project_path": .string(fixture.project),
                "storekit_path": .string(fixture.storekit),
                "scheme_name": .string("App"),
                "test_target": .string("AppTests"),
            ])

        #expect(message.contains("file reference"))
        #expect(message.contains("AppTests"))
        #expect(message.contains("../../../Config.storekit"))
        // A correctly-configured add reports no warnings.
        #expect(!message.contains("Warnings:"))

        // The scheme is wired on both actions with the scheme-relative identifier.
        let scheme = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        let refCount = scheme.components(separatedBy: "<StoreKitConfigurationFileReference").count
            - 1
        #expect(refCount == 2)
        #expect(scheme.contains("identifier = \"../../../Config.storekit\""))

        // The file reference is a project member and a resource of the test target only.
        let xcodeproj = try XcodeProj(path: Path(fixture.project))
        let ref = try #require(xcodeproj.pbxproj.fileReferences.first {
            ($0.name ?? $0.path) == "Config.storekit"
        })
        let testTarget = try #require(xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "AppTests"
        })
        let appTarget = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        #expect(resources(of: testTarget).contains { $0.file === ref })
        #expect(!resources(of: appTarget).contains { $0.file === ref })
    }

    @Test
    func `Add is idempotent across project and scheme`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let args: [String: Value] = [
            "project_path": .string(fixture.project),
            "storekit_path": .string(fixture.storekit),
            "scheme_name": .string("App"),
            "test_target": .string("AppTests"),
        ]
        _ = try runAdd(base: fixture.base, arguments: args)
        let second = try runAdd(base: fixture.base, arguments: args)
        #expect(second.contains("already a member"))

        let xcodeproj = try XcodeProj(path: Path(fixture.project))
        let testTarget = try #require(xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "AppTests"
        })
        let storekitBuildFiles = resources(of: testTarget).filter {
            ($0.file as? PBXFileReference)?.name == "Config.storekit"
        }
        #expect(storekitBuildFiles.count == 1, "Repeat add must not duplicate the resource")

        let scheme = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        let refCount = scheme.components(separatedBy: "<StoreKitConfigurationFileReference").count
            - 1
        #expect(refCount == 2)
    }

    @Test
    func `Adding to a non-test target warns`() throws {
        let fixture = try Self.makeFixture(testTargetType: .application)
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try runAdd(
            base: fixture.base,
            arguments: [
                "project_path": .string(fixture.project),
                "storekit_path": .string(fixture.storekit),
                "scheme_name": .string("App"),
                "test_target": .string("AppTests"),
            ])
        #expect(message.contains("Warnings:"))
        #expect(message.contains("not a unit/UI test bundle"))

        // The config must NOT be bundled into the non-test (application) target's resources —
        // that's the antipattern the warning is about.
        let xcodeproj = try XcodeProj(path: Path(fixture.project))
        let target = try #require(
            xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTests" },
        )
        #expect(!resources(of: target).contains {
            ($0.file as? PBXFileReference)?.name == "Config.storekit"
        })
    }

    @Test
    func `Add without a scheme warns that config stays inactive`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try runAdd(
            base: fixture.base,
            arguments: [
                "project_path": .string(fixture.project),
                "storekit_path": .string(fixture.storekit),
            ])
        #expect(message.contains("no scheme_name"))
        // The scheme is untouched.
        let scheme = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        #expect(!scheme.contains("StoreKitConfigurationFileReference"))
    }

    @Test
    func `Non-storekit path is rejected`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let notStorekit = (fixture.base as NSString).appendingPathComponent("Config.json")
        try "{}".write(toFile: notStorekit, atomically: true, encoding: .utf8)

        #expect(throws: MCPError.self) {
            _ = try addTool(base: fixture.base).execute(arguments: [
                "project_path": .string(fixture.project),
                "storekit_path": .string(notStorekit),
            ])
        }
    }

    @Test
    func `remove_file on a storekit unwires the scheme and warns`() throws {
        let fixture = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        _ = try runAdd(
            base: fixture.base,
            arguments: [
                "project_path": .string(fixture.project),
                "storekit_path": .string(fixture.storekit),
                "scheme_name": .string("App"),
                "test_target": .string("AppTests"),
            ])

        let removeTool = RemoveFileTool(pathUtility: PathUtility(basePath: fixture.base))
        let result = try removeTool.execute(arguments: [
            "project_path": .string(fixture.project),
            "file_path": .string(fixture.storekit),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }

        #expect(message.contains("Unwired StoreKit reference"))
        #expect(message.contains("SKTestSession"))

        // The scheme no longer points at the removed config.
        let scheme = try String(contentsOfFile: fixture.scheme, encoding: .utf8)
        #expect(!scheme.contains("StoreKitConfigurationFileReference"))
    }

    /// All build files across a target's resources build phases.
    private func resources(of target: PBXNativeTarget) -> [PBXBuildFile] {
        target.buildPhases
            .compactMap { $0 as? PBXResourcesBuildPhase }
            .flatMap { $0.files ?? [] }
    }
}
