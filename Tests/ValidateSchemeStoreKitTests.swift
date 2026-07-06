import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Covers the StoreKit-specific validations added to `validate_scheme` for pzg-2cv: a scheme
/// StoreKit reference whose relative path doesn't resolve, and a `.storekit` shipped in an app
/// target's Copy Bundle Resources.
struct ValidateSchemeStoreKitTests {
    private static func scheme(storekitIdentifier: String?) -> String {
        let launchChild = storekitIdentifier.map {
            """

                  <StoreKitConfigurationFileReference
                     identifier = "\($0)">
                  </StoreKitConfigurationFileReference>
            """
        } ?? ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme version = "1.7">
               <LaunchAction
                  buildConfiguration = "Debug">\(launchChild)
               </LaunchAction>
            </Scheme>

            """
    }

    private static func makeFixture(
        storekitIdentifier: String?,
        writeStorekitAtRoot: Bool,
    ) throws -> (base: String, project: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let projectPath = tempDir.appendingPathComponent("TestProject.xcodeproj")
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: Path(projectPath.path),
        )

        let schemesDir = projectPath.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemesDir, withIntermediateDirectories: true)
        try scheme(storekitIdentifier: storekitIdentifier)
            .write(
                to: schemesDir.appendingPathComponent("App.xcscheme"),
                atomically: true, encoding: .utf8)

        if writeStorekitAtRoot {
            try "{}".write(
                to: tempDir.appendingPathComponent("Config.storekit"),
                atomically: true, encoding: .utf8)
        }
        return (tempDir.path, projectPath.path)
    }

    private func validate(base: String, project: String) throws -> String {
        let tool = ValidateSchemeTool(pathUtility: PathUtility(basePath: base))
        let result = try tool.execute(arguments: [
            "project_path": .string(project),
            "scheme_name": .string("App"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return ""
        }
        return message
    }

    @Test
    func `Resolving StoreKit reference is valid`() throws {
        // Scheme at .../xcshareddata/xcschemes/App.xcscheme, config at repo root → ../../../.
        let fixture = try Self.makeFixture(
            storekitIdentifier: "../../../Config.storekit", writeStorekitAtRoot: true,
        )
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try validate(base: fixture.base, project: fixture.project)
        #expect(message.contains("is valid"))
    }

    @Test
    func `Wrong relative depth is flagged`() throws {
        // The classic pzg-2cv corruption: ../../ (2 levels) instead of ../../../ points at nothing.
        let fixture = try Self.makeFixture(
            storekitIdentifier: "../../Config.storekit", writeStorekitAtRoot: true,
        )
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let message = try validate(base: fixture.base, project: fixture.project)
        #expect(message.contains("does not resolve"))
    }

    @Test
    func `StoreKit config in app target resources is flagged`() throws {
        let fixture = try Self.makeFixture(storekitIdentifier: nil, writeStorekitAtRoot: true)
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        // Put the .storekit into the App target's resources — the shipped-in-app antipattern.
        let xcodeproj = try XcodeProj(path: Path(fixture.project))
        let ref = PBXFileReference(
            sourceTree: .sourceRoot, name: "Config.storekit",
            lastKnownFileType: "text", path: "Config.storekit",
        )
        xcodeproj.pbxproj.add(object: ref)
        let buildFile = PBXBuildFile(file: ref)
        xcodeproj.pbxproj.add(object: buildFile)
        let app = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let resources = try #require(
            app.buildPhases.compactMap { $0 as? PBXResourcesBuildPhase }.first)
        resources.files = (resources.files ?? []) + [buildFile]
        try xcodeproj.write(path: Path(fixture.project))

        let message = try validate(base: fixture.base, project: fixture.project)
        #expect(message.contains("Copy Bundle Resources"))
        #expect(message.contains("should not"))
    }
}
