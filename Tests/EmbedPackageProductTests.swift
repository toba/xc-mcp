import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Covers embedding a Swift package product with `add_to_copy_files_phase`.
///
/// A dynamic package product needs an Embed Frameworks entry carrying `productRef`, or the app dies
/// at dyld with the framework missing from the bundle.
@Suite(.temporaryDirectory)
struct EmbedPackageProductTests {
    private let tempDir = TemporaryDirectory.path
    private let pathUtility = PathUtility(basePath: TemporaryDirectory.path)

    /// Builds a project whose App target links `TobaMarkdown` and holds an empty Embed Frameworks
    /// phase.
    private func makeProject(linking productName: String? = "TobaMarkdown") throws -> Path {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        if let productName {
            let dependency = XCSwiftPackageProductDependency(productName: productName)
            xcodeproj.pbxproj.add(object: dependency)
            target.packageProductDependencies = [dependency]

            let linked = PBXBuildFile(product: dependency)
            xcodeproj.pbxproj.add(object: linked)
            let frameworks = PBXFrameworksBuildPhase(files: [linked])
            xcodeproj.pbxproj.add(object: frameworks)
            target.buildPhases.append(frameworks)
        }

        let embed = PBXCopyFilesBuildPhase(
            dstPath: "", dstSubfolderSpec: .frameworks, name: "Embed Frameworks",
        )
        xcodeproj.pbxproj.add(object: embed)
        target.buildPhases.append(embed)
        try PBXProjWriter.write(xcodeproj, to: projectPath)
        return projectPath
    }

    /// The entries of the App target's Embed Frameworks phase, in order.
    private func entries(of projectPath: Path) throws -> [PBXBuildFile] {
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = try #require(
            target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }.first)
        return phase.files ?? []
    }

    private func addTobaMarkdown(
        to projectPath: Path,
        platformFilters: [Value]? = nil,
    ) throws -> CallTool.Result {
        var arguments: [String: Value] = [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Embed Frameworks"),
            "files": .array([.string("TobaMarkdown")]),
        ]
        if let platformFilters { arguments["platform_filters"] = .array(platformFilters) }
        return try AddToCopyFilesPhase(pathUtility: pathUtility).execute(arguments: arguments)
    }

    @Test
    func `Embeds a package product the target links`() throws {
        let projectPath = try makeProject()

        let text = try message(of: addTobaMarkdown(to: projectPath))
        #expect(text.contains("TobaMarkdown"))
        #expect(!text.contains("not found in project"))

        let entry = try #require(entries(of: projectPath).first)
        #expect(entry.product?.productName == "TobaMarkdown")
        #expect(entry.file == nil)
        #expect(entry.attributes == ["CodeSignOnCopy", "RemoveHeadersOnCopy"])
    }

    @Test
    func `An embedded product carries the requested platform filters`() throws {
        let projectPath = try makeProject()

        _ = try addTobaMarkdown(to: projectPath, platformFilters: [.string("macos")])

        let entry = try #require(entries(of: projectPath).first)
        #expect(entry.platformFilters == ["macos"])
    }

    @Test
    func `The embed entry reuses the product dependency the target links`() throws {
        let projectPath = try makeProject()

        _ = try addTobaMarkdown(to: projectPath)

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let linked = try #require(target.packageProductDependencies?.first)
        let phase = try #require(
            target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }.first)
        let entry = try #require(phase.files?.first)
        #expect(entry.product?.uuid == linked.uuid)
        #expect(target.packageProductDependencies?.count == 1)
    }

    @Test
    func `A second call reports the product as already present`() throws {
        let projectPath = try makeProject()

        _ = try addTobaMarkdown(to: projectPath)
        let text = try message(of: addTobaMarkdown(to: projectPath))

        #expect(text.contains("already present"))
        #expect(try entries(of: projectPath).count == 1)
    }

    @Test
    func `A product the target does not link names add_package_product`() throws {
        let projectPath = try makeProject(linking: nil)

        let text = try message(of: addTobaMarkdown(to: projectPath))

        #expect(text.contains("not found in project"))
        #expect(text.contains("add_package_product"))
        #expect(try entries(of: projectPath).isEmpty)
    }
}
