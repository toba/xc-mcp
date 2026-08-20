import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Covers SwiftPM package traits on remote and local package references.
///
/// Each test writes the project file and reads it back, so a trait must survive the project writer
/// and the decoder.
@Suite(.temporaryDirectory)
struct SwiftPackageTraitsTests {
    /// Creates a temporary directory and an empty test project inside it.
    private func makeProject(
        targetName: String? = nil,
    ) throws -> (dir: URL, path: Path) {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"

        if let targetName {
            try TestProjectHelper.createTestProjectWithTarget(
                name: "TestProject", targetName: targetName, at: projectPath,
            )
        } else {
            try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        }
        return (tempDir, projectPath)
    }

    /// Reads the traits of a remote package reference from the project file on disk.
    ///
    /// The loaded project stays alive for the whole read. A package reference resolves through the
    /// object graph, so it reports nothing once the graph goes away.
    private func remoteTraits(at projectPath: Path, url: String) throws -> [String]? {
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try #require(try xcodeproj.pbxproj.rootProject())
        let reference = try #require(project.remotePackages.first(where: { $0.repositoryURL == url }
            ))
        return reference.traits
    }

    /// Reads the traits of a local package reference from the project file on disk.
    private func localTraits(at projectPath: Path, relativePath: String) throws -> [String]? {
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try #require(try xcodeproj.pbxproj.rootProject())
        let reference = try #require(project.localPackages.first(where: {
            $0.relativePath == relativePath
        }))
        return reference.traits
    }

    // MARK: - Argument parsing

    @Test
    func `Omitted traits argument parses as nil`() {
        #expect(SwiftPackageTraits.parse(from: ["project_path": .string("/tmp/x")]) == nil)
    }

    @Test
    func `Traits argument drops duplicates and keeps order`() {
        let parsed = SwiftPackageTraits.parse(from: [
            "traits": .array([.string("Networking"), .string("Logging"), .string("Networking")])
        ])
        #expect(parsed == ["Networking", "Logging"])
    }

    @Test
    func `Empty traits array stores nil`() {
        #expect(SwiftPackageTraits.parse(from: ["traits": .array([])]) == [])
        #expect(SwiftPackageTraits.stored([]) == nil)
    }

    // MARK: - add_swift_package

    @Test
    func `Add remote package with traits`() throws {
        let (dir, projectPath) = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        let url = "https://github.com/apple/swift-log.git"
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_url": .string(url),
            "requirement": .string("from: 1.0.0"),
            "traits": .array([.string("Networking"), .string("Logging")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("enabled package traits: Networking, Logging"))

        #expect(try remoteTraits(at: projectPath, url: url) == ["Networking", "Logging"])
    }

    @Test
    func `Add local package with traits`() throws {
        let (dir, projectPath) = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_path": .string("../MyLocalPackage"),
            "traits": .array([.string("Experimental")]),
        ])

        #expect(
            try localTraits(at: projectPath, relativePath: "../MyLocalPackage") == ["Experimental"],
        )
    }

    @Test
    func `Add remote package without traits leaves the key unset`() throws {
        let (dir, projectPath) = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        let url = "https://github.com/apple/swift-log.git"
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_url": .string(url),
            "requirement": .string("from: 1.0.0"),
        ])

        #expect(try remoteTraits(at: projectPath, url: url) == nil)
    }

    @Test
    func `Traits on an existing remote package replace the old traits`() throws {
        let (dir, projectPath) = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        let url = "https://github.com/apple/swift-log.git"
        let arguments: [String: Value] = [
            "project_path": .string(projectPath.string),
            "package_url": .string(url),
            "requirement": .string("from: 1.0.0"),
        ]
        _ = try tool.execute(arguments: arguments.merging([
            "traits": .array([.string("Networking")])
        ]) { _, new in new },
        )
        _ = try tool.execute(arguments: arguments.merging(["traits": .array([.string("Logging")])])
            { _, new in new },
        )

        #expect(try remoteTraits(at: projectPath, url: url) == ["Logging"])
    }

    @Test
    func `Empty traits array clears traits on an existing local package`() throws {
        let (dir, projectPath) = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        let arguments: [String: Value] = [
            "project_path": .string(projectPath.string),
            "package_path": .string("../MyLocalPackage"),
        ]
        _ = try tool.execute(arguments: arguments.merging([
            "traits": .array([.string("Experimental")])
        ]) { _, new in new },
        )

        let result = try tool.execute(arguments: arguments.merging(["traits": .array([])]) {
            _, new in new
        })
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("cleared package traits"))

        #expect(try localTraits(at: projectPath, relativePath: "../MyLocalPackage") == nil)
    }

    // MARK: - add_package_product

    @Test
    func `Add package product sets traits on the remote reference`() throws {
        let (dir, projectPath) = try makeProject(targetName: "App")
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = "https://github.com/apple/swift-log.git"
        let addPackage = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        _ = try addPackage.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_url": .string(url),
            "requirement": .string("from: 1.0.0"),
        ])

        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: dir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "product_name": .string("Logging"),
            "package_url": .string(url),
            "traits": .array([.string("Networking")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("enabled package traits: Networking"))

        #expect(try remoteTraits(at: projectPath, url: url) == ["Networking"])
    }

    @Test
    func `Add package product sets traits on the local reference`() throws {
        let (dir, projectPath) = try makeProject(targetName: "App")
        defer { try? FileManager.default.removeItem(at: dir) }

        let addPackage = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        _ = try addPackage.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_path": .string("../MyLocalPackage"),
        ])

        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: dir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "product_name": .string("MyLibrary"),
            "package_path": .string("../MyLocalPackage"),
            "traits": .array([.string("Experimental")]),
        ])

        #expect(
            try localTraits(at: projectPath, relativePath: "../MyLocalPackage") == ["Experimental"],
        )
    }

    @Test
    func `Add package product rejects traits without a package reference`() throws {
        let (dir, projectPath) = try makeProject(targetName: "App")
        defer { try? FileManager.default.removeItem(at: dir) }

        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: dir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "product_name": .string("Logging"),
                "traits": .array([.string("Networking")]),
            ])
        }
    }

    // MARK: - list_swift_packages

    @Test
    func `List reports traits for remote and local packages`() throws {
        let (dir, projectPath) = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }

        let addPackage = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        _ = try addPackage.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_url": .string("https://github.com/apple/swift-log.git"),
            "requirement": .string("from: 1.0.0"),
            "traits": .array([.string("Networking"), .string("Logging")]),
        ])
        _ = try addPackage.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_path": .string("../MyLocalPackage"),
            "traits": .array([.string("Experimental")]),
        ])

        let listTool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: dir.path))
        let result = try listTool.execute(arguments: ["project_path": .string(projectPath.string)])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("[traits: Networking, Logging]"))
        #expect(message.contains("[traits: Experimental]"))
    }

    @Test
    func `List omits the traits suffix when a package has none`() throws {
        let (dir, projectPath) = try makeProject()
        defer { try? FileManager.default.removeItem(at: dir) }

        let addPackage = AddSwiftPackageTool(pathUtility: PathUtility(basePath: dir.path))
        _ = try addPackage.execute(arguments: [
            "project_path": .string(projectPath.string),
            "package_url": .string("https://github.com/apple/swift-log.git"),
            "requirement": .string("from: 1.0.0"),
        ])

        let listTool = ListSwiftPackagesTool(pathUtility: PathUtility(basePath: dir.path))
        let result = try listTool.execute(arguments: ["project_path": .string(projectPath.string)])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(!message.contains("traits"))
    }
}
