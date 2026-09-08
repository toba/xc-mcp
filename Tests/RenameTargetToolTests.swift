import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct RenameTargetToolTests {
    @Test
    func `Tool creation`() {
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "rename_target")
        #expect(
            toolDefinition.description
                == "Rename an existing target in-place, updating all references",
        )
    }

    @Test
    func `Rename target with missing parameters`() throws {
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "new_name": Value.string("NewApp"),
            ])
        }

        // Missing target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "new_name": Value.string("NewApp"),
            ])
        }

        // Missing new_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
            ])
        }
    }

    @Test
    func `Rename existing target`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed target 'App' to 'NewApp'"))

        // Verify target was renamed
        let xcodeproj = try XcodeProj(path: projectPath)
        let renamedTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "NewApp" }
        #expect(renamedTarget != nil)

        // Verify old name is gone
        let oldTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        #expect(oldTarget == nil)

        // Verify PRODUCT_NAME updated
        let buildConfig = renamedTarget?.buildConfigurationList?.buildConfigurations.first
        #expect(buildConfig?.buildSettings["PRODUCT_NAME"]?.stringValue == "NewApp")

        // Verify BUNDLE_IDENTIFIER preserved (not changed)
        #expect(buildConfig?.buildSettings["BUNDLE_IDENTIFIER"]?.stringValue == "com.example.App")
    }

    @Test
    func `Rename non-existent target`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "new_name": Value.string("NewTarget"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `Rename to existing target name`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add another target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("ExistingTarget"),
            "product_type": Value.string("app"),
            "bundle_identifier": Value.string("com.test.existing"),
        ])

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("ExistingTarget"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test
    func `Rename target with dependencies`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a framework target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ])

        // Add dependency: App depends on Framework
        let addDependencyTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addDependencyTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Framework"),
        ])

        // Rename the framework target
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "new_name": Value.string("CoreLib"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify dependency reference was updated
        let xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let hasDependency = appTarget?.dependencies.contains { $0.name == "CoreLib" } ?? false
        #expect(hasDependency == true)
    }

    @Test
    func `Rename target with product reference`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a product reference to the target
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let productRef = PBXFileReference(
            sourceTree: .buildProductsDir, name: "App.app", path: "App.app",
        )
        xcodeproj.pbxproj.add(object: productRef)
        target.product = productRef
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        // Rename the target
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify product reference path was updated
        let updatedProj = try XcodeProj(path: projectPath)
        let renamedTarget = updatedProj.pbxproj.nativeTargets.first { $0.name == "NewApp" }
        #expect(renamedTarget?.product?.path == "NewApp.app")
    }

    // MARK: - New tests for enhanced rename_target

    @Test
    func `Rename target with new bundle identifier`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
            "new_bundle_identifier": Value.string("com.example.NewApp"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify bundle identifiers updated
        let xcodeproj = try XcodeProj(path: projectPath)
        let renamedTarget = try #require(xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "NewApp"
        })

        for config in renamedTarget.buildConfigurationList?.buildConfigurations ?? [] {
            #expect(
                config.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?
                    .stringValue
                    == "com.example.NewApp",
            )
            #expect(config.buildSettings["BUNDLE_IDENTIFIER"]?.stringValue == "com.example.NewApp")
        }
    }

    @Test
    func `Rename target updates CODE_SIGN_ENTITLEMENTS`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add CODE_SIGN_ENTITLEMENTS to build settings
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        for config in target.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["CODE_SIGN_ENTITLEMENTS"] = .string("App/App.entitlements")
        }
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify entitlements path updated
        let updatedProj = try XcodeProj(path: projectPath)
        let renamedTarget = try #require(updatedProj.pbxproj.nativeTargets.first {
            $0.name == "NewApp"
        })
        let config = try #require(renamedTarget.buildConfigurationList?.buildConfigurations.first)
        #expect(
            config.buildSettings["CODE_SIGN_ENTITLEMENTS"]?
                .stringValue
                == "NewApp/NewApp.entitlements",
        )
    }

    @Test
    func `Rename target updates cross-target TEST_TARGET_NAME and TEST_HOST`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a test target with TEST_TARGET_NAME and TEST_HOST
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("AppTests"),
            "product_type": Value.string("unit_test_bundle"),
            "bundle_identifier": Value.string("com.example.AppTests"),
        ])

        // Set TEST_TARGET_NAME and TEST_HOST on the test target
        let xcodeproj = try XcodeProj(path: projectPath)
        let testTarget = try #require(xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "AppTests"
        })

        for config in testTarget.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["TEST_TARGET_NAME"] = .string("App")
            config.buildSettings["TEST_HOST"] = .string(
                "$(BUILT_PRODUCTS_DIR)/App.app/Contents/MacOS/App",
            )
        }
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        // Rename the app target
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify test target settings updated
        let updatedProj = try XcodeProj(path: projectPath)
        let updatedTestTarget = try #require(updatedProj.pbxproj.nativeTargets.first {
            $0.name == "AppTests"
        })
        let config = try #require(
            updatedTestTarget.buildConfigurationList?.buildConfigurations.first,
        )
        #expect(config.buildSettings["TEST_TARGET_NAME"]?.stringValue == "NewApp")
        #expect(
            config.buildSettings["TEST_HOST"]?
                .stringValue
                == "$(BUILT_PRODUCTS_DIR)/NewApp.app/Contents/MacOS/NewApp",
        )
    }

    @Test
    func `Rename target updates scheme files`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Create a scheme file with BuildableName and BlueprintName
        let schemesDir = projectPath.string + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(
            atPath: schemesDir, withIntermediateDirectories: true,
        )
        let schemeContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme>
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "ABC123"
                  BuildableName = "App.app"
                  BlueprintName = "App"
                  ReferencedContainer = "container:TestProject.xcodeproj">
               </BuildableReference>
            </Scheme>
            """
        try schemeContent.write(
            toFile: "\(schemesDir)/App.xcscheme", atomically: true, encoding: .utf8,
        )

        // Rename the target
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))
        #expect(message.contains("updated 1 scheme file"))

        // Verify scheme file content was updated
        let updatedScheme = try String(
            contentsOfFile: "\(schemesDir)/App.xcscheme", encoding: .utf8,
        )
        #expect(updatedScheme.contains("BuildableName = \"NewApp.app\""))
        #expect(updatedScheme.contains("BlueprintName = \"NewApp\""))
        #expect(!updatedScheme.contains("BuildableName = \"App.app\""))
        #expect(!updatedScheme.contains("BlueprintName = \"App\""))
    }

    @Test
    func `Rename target updates LD_RUNPATH_SEARCH_PATHS and FRAMEWORK_SEARCH_PATHS`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Set search paths that reference the target name
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        for config in target.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] = .array([
                "$(inherited)",
                "@executable_path/../Frameworks/App",
            ])
            config.buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string(
                "$(BUILT_PRODUCTS_DIR)/App/Frameworks",
            )
        }
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        // Rename the target
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify search paths updated
        let updatedProj = try XcodeProj(path: projectPath)
        let renamedTarget = try #require(updatedProj.pbxproj.nativeTargets.first {
            $0.name == "NewApp"
        })
        let config = try #require(renamedTarget.buildConfigurationList?.buildConfigurations.first)

        // LD_RUNPATH_SEARCH_PATHS (array value)
        if case let .array(ldPaths) = config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] {
            #expect(ldPaths.contains("@executable_path/../Frameworks/NewApp"))
            #expect(!ldPaths.contains("@executable_path/../Frameworks/App"))
        } else {
            Issue.record("Expected array value for LD_RUNPATH_SEARCH_PATHS")
        }

        // FRAMEWORK_SEARCH_PATHS (string value)
        #expect(
            config.buildSettings["FRAMEWORK_SEARCH_PATHS"]?
                .stringValue
                == "$(BUILT_PRODUCTS_DIR)/NewApp/Frameworks",
        )
    }

    // MARK: - Whole-name matching

    /// Builds the project from the bug report: a tool target named `jig`, an app target named
    /// `jig-direct`, and an embed phase in the app carrying the tool's product.
    private func makeSiblingProject(at projectPath: Path) throws {
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "jig", target2: "jig-direct", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let pbxproj = xcodeproj.pbxproj
        let tool = try #require(pbxproj.nativeTargets.first { $0.name == "jig" })
        let app = try #require(pbxproj.nativeTargets.first { $0.name == "jig-direct" })

        tool.productType = .commandLineTool

        let toolProduct = PBXFileReference(sourceTree: .buildProductsDir, name: "jig", path: "jig")
        let appProduct = PBXFileReference(
            sourceTree: .buildProductsDir, name: "jig-direct.app", path: "jig-direct.app",
        )
        pbxproj.add(object: toolProduct)
        pbxproj.add(object: appProduct)
        tool.product = toolProduct
        app.product = appProduct

        let embedFile = PBXBuildFile(file: toolProduct)
        pbxproj.add(object: embedFile)
        let embedPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .executables,
            name: "Embed Tool",
            files: [embedFile],
        )
        pbxproj.add(object: embedPhase)
        app.buildPhases.append(embedPhase)

        try PBXProjWriter.write(xcodeproj, to: projectPath)
    }

    @Test
    func `Rename target leaves a sibling target's product path alone`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try makeSiblingProject(at: projectPath)

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("jig"),
            "new_name": Value.string("jig-cli"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        let updatedProj = try XcodeProj(path: projectPath)
        let renamed = try #require(updatedProj.pbxproj.nativeTargets.first { $0.name == "jig-cli" })
        let sibling = try #require(updatedProj.pbxproj.nativeTargets.first {
            $0.name == "jig-direct"
        })

        // The renamed target's product takes the new name exactly once.
        #expect(renamed.product?.path == "jig-cli")
        #expect(renamed.product?.name == "jig-cli")

        // The sibling target is not being renamed, so its product keeps its name.
        #expect(sibling.product?.path == "jig-direct.app")
        #expect(sibling.product?.name == "jig-direct.app")
    }

    @Test
    func `Rename target leaves the product path alone when PRODUCT_NAME differs`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let productRef = PBXFileReference(
            sourceTree: .buildProductsDir, name: "App.app", path: "App.app",
        )
        xcodeproj.pbxproj.add(object: productRef)
        target.product = productRef

        for config in target.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["PRODUCT_NAME"] = .string("Branded")
        }
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("PRODUCT_NAME"))

        let updatedProj = try XcodeProj(path: projectPath)
        let renamed = try #require(updatedProj.pbxproj.nativeTargets.first { $0.name == "NewApp" })
        #expect(renamed.product?.path == "App.app")

        // PRODUCT_NAME does not name the old target, so the rename leaves it set.
        let config = try #require(renamed.buildConfigurationList?.buildConfigurations.first)
        #expect(config.buildSettings["PRODUCT_NAME"]?.stringValue == "Branded")
    }

    @Test
    func `Rename target leaves a sibling name inside a build setting alone`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try makeSiblingProject(at: projectPath)

        let xcodeproj = try XcodeProj(path: projectPath)
        let app = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "jig-direct" })

        for config in app.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["TEST_HOST"] = .string(
                "$(BUILT_PRODUCTS_DIR)/jig-direct.app/Contents/MacOS/jig-direct",
            )
            config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] = .array([
                "$(inherited)",
                "@executable_path/../Frameworks/jig-direct",
                "@executable_path/../Helpers/jig",
            ])
        }
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("jig"),
            "new_name": Value.string("jig-cli"),
        ])

        let updatedProj = try XcodeProj(path: projectPath)
        let updatedApp = try #require(updatedProj.pbxproj.nativeTargets.first {
            $0.name == "jig-direct"
        })
        let config = try #require(updatedApp.buildConfigurationList?.buildConfigurations.first)

        #expect(
            config.buildSettings["TEST_HOST"]?
                .stringValue
                == "$(BUILT_PRODUCTS_DIR)/jig-direct.app/Contents/MacOS/jig-direct",
        )

        guard case let .array(paths) = config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] else {
            Issue.record("Expected array value for LD_RUNPATH_SEARCH_PATHS")
            return
        }
        #expect(paths.contains("@executable_path/../Frameworks/jig-direct"))
        #expect(paths.contains("@executable_path/../Helpers/jig-cli"))
    }

    @Test
    func `Rename target reports each rewritten reference`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        for config in target.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["CODE_SIGN_ENTITLEMENTS"] = .string("App/App.entitlements")
        }
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("CODE_SIGN_ENTITLEMENTS"))
        #expect(message.contains("App/App.entitlements"))
        #expect(message.contains("NewApp/NewApp.entitlements"))
    }

    @Test
    func `Rename target updates a scheme buildable name without an extension`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try makeSiblingProject(at: projectPath)

        let schemesDir = projectPath.string + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(
            atPath: schemesDir, withIntermediateDirectories: true,
        )
        let schemeContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme>
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "ABC123"
                  BuildableName = "jig"
                  BlueprintName = "jig"
                  ReferencedContainer = "container:TestProject.xcodeproj">
               </BuildableReference>
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "DEF456"
                  BuildableName = "jig-direct.app"
                  BlueprintName = "jig-direct"
                  ReferencedContainer = "container:TestProject.xcodeproj">
               </BuildableReference>
            </Scheme>
            """
        try schemeContent.write(
            toFile: "\(schemesDir)/jig.xcscheme", atomically: true, encoding: .utf8,
        )

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("jig"),
            "new_name": Value.string("jig-cli"),
        ])

        let updatedScheme = try String(
            contentsOfFile: "\(schemesDir)/jig.xcscheme", encoding: .utf8,
        )
        #expect(updatedScheme.contains("BuildableName = \"jig-cli\""))
        #expect(updatedScheme.contains("BlueprintName = \"jig-cli\""))
        #expect(updatedScheme.contains("BuildableName = \"jig-direct.app\""))
        #expect(updatedScheme.contains("BlueprintName = \"jig-direct\""))
    }
}
