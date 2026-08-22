import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct RemoveSubprojectToolTests {
    // MARK: - Fixture

    /// Builds a consumer project that links two products out of one sub-project bundle.
    ///
    /// The shape matches what Xcode writes for a cross-project dependency: a `wrapper.pb-project`
    /// file reference for the child bundle, a Products group of `PBXReferenceProxy` objects, a
    /// `PBXContainerItemProxy` behind each proxy, build files in both the Link Binary and the Embed
    /// Frameworks phases, and one `PBXTargetDependency` edge.
    ///
    /// - Parameters:
    ///   - tempDir: Directory the project is written into.
    ///   - subprojectRelativePath: Path of the child bundle, relative to the consumer project.
    ///   - extraEmbeddedFramework: A plain framework also embedded, to prove the phase survives.
    /// - Returns: The path of the consumer `.xcodeproj`.
    @discardableResult
    static func makeProjectWithSubproject(
        in tempDir: URL,
        subprojectRelativePath: String = "Storage/GRDB/GRDBCustom.xcodeproj",
        extraEmbeddedFramework: String? = "Other.framework",
    ) throws -> Path {
        let projectPath = Path(tempDir.path) + "Consumer.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Consumer", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let pbxproj = xcodeproj.pbxproj
        let rootObject = pbxproj.rootObject!
        let app = pbxproj.nativeTargets.first { $0.name == "App" }!

        let subprojectRef = PBXFileReference(
            sourceTree: .group,
            name: (subprojectRelativePath as NSString).lastPathComponent,
            lastKnownFileType: "wrapper.pb-project",
            path: subprojectRelativePath,
        )
        pbxproj.add(object: subprojectRef)
        rootObject.mainGroup.children.append(subprojectRef)

        let productGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productGroup)

        let frameworksPhase = PBXFrameworksBuildPhase()
        pbxproj.add(object: frameworksPhase)
        app.buildPhases.append(frameworksPhase)

        let embedPhase = PBXCopyFilesBuildPhase(
            dstPath: "", dstSubfolderSpec: .frameworks, name: "Embed Frameworks",
        )
        pbxproj.add(object: embedPhase)
        app.buildPhases.append(embedPhase)

        // Two vended products, so the removal has to sweep more than one proxy.
        for (index, product) in ["GRDB.framework", "GRDBTools.framework"].enumerated() {
            let containerProxy = PBXContainerItemProxy(
                containerPortal: .fileReference(subprojectRef),
                remoteGlobalID: .string("F3BA805A1CFB2BB2003DC1B\(index)"),
                proxyType: .reference,
                remoteInfo: "GRDBCustom",
            )
            pbxproj.add(object: containerProxy)

            let referenceProxy = PBXReferenceProxy(
                fileType: "wrapper.framework",
                path: product,
                remote: containerProxy,
                sourceTree: .buildProductsDir,
            )
            pbxproj.add(object: referenceProxy)
            productGroup.children.append(referenceProxy)

            let linkFile = PBXBuildFile(file: referenceProxy)
            pbxproj.add(object: linkFile)
            frameworksPhase.files?.append(linkFile)

            let embedFile = PBXBuildFile(
                file: referenceProxy,
                settings: ["ATTRIBUTES": .array(["CodeSignOnCopy", "RemoveHeadersOnCopy"])],
            )
            pbxproj.add(object: embedFile)
            embedPhase.files?.append(embedFile)
        }

        // One ordering edge, the proxyType 1 sibling of the reference proxies above.
        let dependencyProxy = PBXContainerItemProxy(
            containerPortal: .fileReference(subprojectRef),
            remoteGlobalID: .string("F3BA805A1CFB2BB2003DC1BA"),
            proxyType: .nativeTarget,
            remoteInfo: "GRDBCustom",
        )
        pbxproj.add(object: dependencyProxy)
        let dependency = PBXTargetDependency(
            name: "GRDBCustom", target: nil, targetProxy: dependencyProxy,
        )
        pbxproj.add(object: dependency)
        app.dependencies.append(dependency)

        if let extraEmbeddedFramework {
            let plainRef = PBXFileReference(
                sourceTree: .group,
                name: extraEmbeddedFramework,
                lastKnownFileType: "wrapper.framework",
                path: extraEmbeddedFramework,
            )
            pbxproj.add(object: plainRef)
            rootObject.mainGroup.children.append(plainRef)
            let plainBuildFile = PBXBuildFile(file: plainRef)
            pbxproj.add(object: plainBuildFile)
            embedPhase.files?.append(plainBuildFile)
        }

        rootObject.projects.append(["ProjectRef": subprojectRef, "ProductGroup": productGroup])

        try xcodeproj.write(path: projectPath)
        return projectPath
    }

    static func text(_ result: CallTool.Result) throws -> String {
        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return content
    }

    // MARK: - Metadata

    @Test
    func `Tool metadata`() {
        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: "/tmp")).tool()
        #expect(tool.name == "remove_subproject")
    }

    @Test
    func `Missing parameters throw`() throws {
        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) { try tool.execute(arguments: [:]) }
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/x.xcodeproj")])
        }
    }

    // MARK: - Removal

    @Test
    func `Removes the file reference, proxies, build files and dependency edge`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)

        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "subproject_path": .string("GRDBCustom.xcodeproj"),
        ]))
        #expect(message.contains("Removed sub-project"))

        let reloaded = try XcodeProj(path: projectPath)
        let pbxproj = reloaded.pbxproj

        #expect(pbxproj.rootObject!.projects.isEmpty)
        #expect(pbxproj.referenceProxies.isEmpty)
        #expect(pbxproj.containerItemProxies.isEmpty)
        #expect(pbxproj.targetDependencies.isEmpty)
        #expect(!pbxproj.fileReferences.contains { $0.path == "Storage/GRDB/GRDBCustom.xcodeproj" })

        let app = pbxproj.nativeTargets.first { $0.name == "App" }!
        #expect(app.dependencies.isEmpty)

        let frameworks = app.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }.first!
        #expect(frameworks.files?.isEmpty ?? true)
    }

    @Test
    func `Leaves the embed phase and its unrelated entry in place`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)

        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "subproject_path": .string("Storage/GRDB/GRDBCustom.xcodeproj"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let app = reloaded.pbxproj.nativeTargets.first { $0.name == "App" }!
        let embed = app.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Embed Frameworks" }
        #expect(embed != nil)
        #expect(embed?.files?.count == 1)
        #expect(embed?.files?.first?.file?.path == "Other.framework")
    }

    @Test
    func `Writes a project with no dangling object reference`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)

        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "subproject_path": .string("GRDBCustom.xcodeproj"),
        ])

        let data = try Data(contentsOf: URL(
            fileURLWithPath: (projectPath + "project.pbxproj")
                .string))
        #expect(PBXProjReferenceAudit.danglingReferences(in: data).isEmpty)
    }

    @Test
    func `Reports the removed objects`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)

        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "subproject_path": .string("GRDBCustom.xcodeproj"),
        ]))
        #expect(message.contains("2 reference proxies"))
        #expect(message.contains("GRDB.framework"))
        #expect(message.contains("3 container item proxies"))
        #expect(message.contains("4 build file entries"))
        #expect(message.contains("1 target dependency edge"))
        #expect(message.contains("affected targets: App"))
    }

    // MARK: - Dry run and matching

    @Test
    func `Dry run writes nothing`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)
        let before = try Data(contentsOf: URL(
            fileURLWithPath: (projectPath + "project.pbxproj")
                .string))

        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "subproject_path": .string("GRDBCustom.xcodeproj"),
            "dry_run": .bool(true),
        ]))
        #expect(message.contains("Dry run"))

        let after = try Data(contentsOf: URL(
            fileURLWithPath: (projectPath + "project.pbxproj")
                .string))
        #expect(before == after)
    }

    @Test
    func `Reports an unreferenced sub-project`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)

        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "subproject_path": .string("Ghost.xcodeproj"),
        ]))
        #expect(message.contains("is not referenced"))
        #expect(message.contains("GRDBCustom.xcodeproj"))
    }

    @Test
    func `Matches a relative path as well as a bare bundle name`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)

        let tool = RemoveSubprojectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "subproject_path": .string("GRDB/GRDBCustom.xcodeproj"),
        ]))
        #expect(message.contains("Removed sub-project"))
    }

    @Test
    func `remove_framework points at remove_subproject for a cross-project product`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProjectWithSubproject(in: tempDir)

        let tool = RemoveFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "framework_name": .string("GRDB.framework"),
            "target_name": .string("App"),
        ]))
        #expect(message.contains("remove_subproject"))
    }
}
