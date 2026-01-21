import Foundation
import XCMCPCore
import MCP
import PathKit
import XcodeProj

public struct ScaffoldIOSProjectTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "scaffold_ios_project",
            description:
                "Create a new iOS project with a modern workspace + Swift Package Manager architecture. Creates a workspace containing the main app project and a local Swift package for shared code.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the project to create"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Directory where the project will be created"),
                    ]),
                    "organization_name": .object([
                        "type": .string("string"),
                        "description": .string("Organization name for the project"),
                    ]),
                    "bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier prefix (e.g., com.example). The app will use this prefix + project name."
                        ),
                    ]),
                    "deployment_target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Minimum iOS version to support (e.g., '16.0'). Defaults to '17.0'."),
                    ]),
                    "include_tests": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include unit test and UI test targets. Defaults to true."),
                    ]),
                ]),
                "required": .array([.string("project_name"), .string("path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectName) = arguments["project_name"] else {
            throw MCPError.invalidParams("project_name is required")
        }

        guard case let .string(basePath) = arguments["path"] else {
            throw MCPError.invalidParams("path is required")
        }

        let organizationName: String
        if case let .string(value) = arguments["organization_name"] {
            organizationName = value
        } else {
            organizationName = "Organization"
        }

        let bundleIdPrefix: String
        if case let .string(value) = arguments["bundle_identifier"] {
            bundleIdPrefix = value
        } else {
            bundleIdPrefix = "com.example"
        }

        let deploymentTarget: String
        if case let .string(value) = arguments["deployment_target"] {
            deploymentTarget = value
        } else {
            deploymentTarget = "17.0"
        }

        let includeTests: Bool
        if case let .bool(value) = arguments["include_tests"] {
            includeTests = value
        } else {
            includeTests = true
        }

        // Resolve path
        let resolvedBasePath = try pathUtility.resolvePath(from: basePath)

        // Create project directory structure
        let projectDir = URL(fileURLWithPath: resolvedBasePath).appendingPathComponent(projectName)
            .path
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: projectDir) {
            throw MCPError.invalidParams("Directory already exists: \(projectDir)")
        }

        do {
            try fileManager.createDirectory(
                atPath: projectDir, withIntermediateDirectories: true)

            // Create app source directory
            let appDir = URL(fileURLWithPath: projectDir).appendingPathComponent(projectName).path
            try fileManager.createDirectory(atPath: appDir, withIntermediateDirectories: true)

            // Create the Xcode project
            let projectPath = URL(fileURLWithPath: projectDir).appendingPathComponent(
                "\(projectName).xcodeproj"
            ).path
            let pbxproj = PBXProj()
            let project = try createProject(
                pbxproj: pbxproj,
                projectName: projectName,
                organizationName: organizationName,
                bundleIdPrefix: bundleIdPrefix,
                deploymentTarget: deploymentTarget,
                includeTests: includeTests
            )
            pbxproj.add(object: project)
            pbxproj.rootObject = project

            let workspaceData = XCWorkspaceData(children: [])
            let workspace = XCWorkspace(data: workspaceData)
            let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
            try xcodeproj.write(path: Path(projectPath))

            // Create workspace
            let workspacePath = URL(fileURLWithPath: projectDir).appendingPathComponent(
                "\(projectName).xcworkspace"
            ).path
            try createWorkspace(
                at: workspacePath, projectName: projectName, projectPath: projectPath)

            // Create source files
            try createSourceFiles(
                appDir: appDir, projectName: projectName, bundleIdPrefix: bundleIdPrefix)

            // Create Swift package for shared code
            let packageDir = URL(fileURLWithPath: projectDir).appendingPathComponent(
                "\(projectName)Kit"
            ).path
            try createSwiftPackage(
                at: packageDir, packageName: "\(projectName)Kit",
                deploymentTarget: deploymentTarget)

            // Create test directories if needed
            if includeTests {
                let testDir = URL(fileURLWithPath: projectDir).appendingPathComponent(
                    "\(projectName)Tests"
                ).path
                try fileManager.createDirectory(
                    atPath: testDir, withIntermediateDirectories: true)
                try createTestFile(at: testDir, projectName: projectName)

                let uiTestDir = URL(fileURLWithPath: projectDir).appendingPathComponent(
                    "\(projectName)UITests"
                ).path
                try fileManager.createDirectory(
                    atPath: uiTestDir, withIntermediateDirectories: true)
                try createUITestFile(at: uiTestDir, projectName: projectName)
            }

            var resultMessage =
                "Successfully created iOS project '\(projectName)' at \(projectDir)\n\n"
            resultMessage += "Created:\n"
            resultMessage += "  - \(projectName).xcworkspace (workspace)\n"
            resultMessage += "  - \(projectName).xcodeproj (Xcode project)\n"
            resultMessage += "  - \(projectName)/ (app sources)\n"
            resultMessage += "  - \(projectName)Kit/ (Swift package for shared code)\n"
            if includeTests {
                resultMessage += "  - \(projectName)Tests/ (unit tests)\n"
                resultMessage += "  - \(projectName)UITests/ (UI tests)\n"
            }
            resultMessage += "\nOpen the workspace with: open \"\(workspacePath)\""

            return CallTool.Result(content: [.text(resultMessage)])
        } catch let error as MCPError {
            throw error
        } catch {
            // Clean up on failure
            try? fileManager.removeItem(atPath: projectDir)
            throw MCPError.internalError("Failed to create project: \(error.localizedDescription)")
        }
    }

    private func createProject(
        pbxproj: PBXProj,
        projectName: String,
        organizationName: String,
        bundleIdPrefix: String,
        deploymentTarget: String,
        includeTests: Bool
    ) throws -> PBXProject {
        // Create main group
        let mainGroup = PBXGroup(children: [], sourceTree: .group)
        pbxproj.add(object: mainGroup)

        // Create build configurations
        let debugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: createProjectBuildSettings(
                debug: true, deploymentTarget: deploymentTarget))
        let releaseConfig = XCBuildConfiguration(
            name: "Release",
            buildSettings: createProjectBuildSettings(
                debug: false, deploymentTarget: deploymentTarget))
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)

        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release"
        )
        pbxproj.add(object: configList)

        // Create project
        let project = PBXProject(
            name: projectName,
            buildConfigurationList: configList,
            compatibilityVersion: "Xcode 14.0",
            preferredProjectObjectVersion: 56,
            minimizedProjectReferenceProxies: 0,
            mainGroup: mainGroup,
            developmentRegion: "en"
        )

        // Create app target
        let appTarget = try createAppTarget(
            pbxproj: pbxproj,
            project: project,
            projectName: projectName,
            bundleIdPrefix: bundleIdPrefix,
            deploymentTarget: deploymentTarget,
            mainGroup: mainGroup
        )
        project.targets.append(appTarget)

        return project
    }

    private func createAppTarget(
        pbxproj: PBXProj,
        project: PBXProject,
        projectName: String,
        bundleIdPrefix: String,
        deploymentTarget: String,
        mainGroup: PBXGroup
    ) -> PBXNativeTarget {
        // Create source build phase
        let sourcesBuildPhase = PBXSourcesBuildPhase(files: [])
        pbxproj.add(object: sourcesBuildPhase)

        // Create frameworks build phase
        let frameworksBuildPhase = PBXFrameworksBuildPhase(files: [])
        pbxproj.add(object: frameworksBuildPhase)

        // Create resources build phase
        let resourcesBuildPhase = PBXResourcesBuildPhase(files: [])
        pbxproj.add(object: resourcesBuildPhase)

        // Create build configurations for target
        let bundleId = "\(bundleIdPrefix).\(projectName)"
        let debugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: createAppTargetBuildSettings(
                debug: true,
                productName: projectName,
                bundleId: bundleId,
                deploymentTarget: deploymentTarget
            )
        )
        let releaseConfig = XCBuildConfiguration(
            name: "Release",
            buildSettings: createAppTargetBuildSettings(
                debug: false,
                productName: projectName,
                bundleId: bundleId,
                deploymentTarget: deploymentTarget
            )
        )
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)

        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release"
        )
        pbxproj.add(object: configList)

        // Create target
        let target = PBXNativeTarget(
            name: projectName,
            buildConfigurationList: configList,
            buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
            productType: .application
        )
        pbxproj.add(object: target)

        return target
    }

    private func createProjectBuildSettings(debug: Bool, deploymentTarget: String) -> BuildSettings
    {
        var settings: BuildSettings = [
            "ALWAYS_SEARCH_USER_PATHS": .string("NO"),
            "CLANG_ANALYZER_NONNULL": .string("YES"),
            "CLANG_CXX_LANGUAGE_STANDARD": .string("gnu++20"),
            "CLANG_ENABLE_MODULES": .string("YES"),
            "CLANG_ENABLE_OBJC_ARC": .string("YES"),
            "COPY_PHASE_STRIP": .string("NO"),
            "ENABLE_STRICT_OBJC_MSGSEND": .string("YES"),
            "GCC_C_LANGUAGE_STANDARD": .string("gnu17"),
            "GCC_NO_COMMON_BLOCKS": .string("YES"),
            "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
            "MTL_ENABLE_DEBUG_INFO": .string(debug ? "INCLUDE_SOURCE" : "NO"),
            "SDKROOT": .string("iphoneos"),
            "SWIFT_VERSION": .string("5.0"),
        ]

        if debug {
            settings["DEBUG_INFORMATION_FORMAT"] = .string("dwarf")
            settings["ENABLE_TESTABILITY"] = .string("YES")
            settings["GCC_OPTIMIZATION_LEVEL"] = .string("0")
            settings["SWIFT_OPTIMIZATION_LEVEL"] = .string("-Onone")
            settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = .string("DEBUG")
        } else {
            settings["DEBUG_INFORMATION_FORMAT"] = .string("dwarf-with-dsym")
            settings["ENABLE_NS_ASSERTIONS"] = .string("NO")
            settings["GCC_OPTIMIZATION_LEVEL"] = .string("s")
            settings["SWIFT_OPTIMIZATION_LEVEL"] = .string("-O")
            settings["VALIDATE_PRODUCT"] = .string("YES")
        }

        return settings
    }

    private func createAppTargetBuildSettings(
        debug: Bool,
        productName: String,
        bundleId: String,
        deploymentTarget: String
    ) -> BuildSettings {
        var settings: BuildSettings = [
            "ASSETCATALOG_COMPILER_APPICON_NAME": .string("AppIcon"),
            "CODE_SIGN_STYLE": .string("Automatic"),
            "CURRENT_PROJECT_VERSION": .string("1"),
            "GENERATE_INFOPLIST_FILE": .string("YES"),
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": .string("YES"),
            "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": .string("YES"),
            "INFOPLIST_KEY_UILaunchScreen_Generation": .string("YES"),
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
                .string(
                    "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
                ),
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
                .string(
                    "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
                ),
            "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
            "LD_RUNPATH_SEARCH_PATHS": .string("$(inherited) @executable_path/Frameworks"),
            "MARKETING_VERSION": .string("1.0"),
            "PRODUCT_BUNDLE_IDENTIFIER": .string(bundleId),
            "PRODUCT_NAME": .string("$(TARGET_NAME)"),
            "SWIFT_EMIT_LOC_STRINGS": .string("YES"),
            "TARGETED_DEVICE_FAMILY": .string("1,2"),
        ]

        if debug {
            settings["SWIFT_OPTIMIZATION_LEVEL"] = .string("-Onone")
        }

        return settings
    }

    private func createWorkspace(at path: String, projectName: String, projectPath: String) throws {
        let workspaceDataPath = URL(fileURLWithPath: path).appendingPathComponent(
            "contents.xcworkspacedata"
        ).path
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true)

        let content = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace
               version = "1.0">
               <FileRef
                  location = "group:\(projectName).xcodeproj">
               </FileRef>
               <FileRef
                  location = "group:\(projectName)Kit">
               </FileRef>
            </Workspace>
            """
        try content.write(toFile: workspaceDataPath, atomically: true, encoding: .utf8)
    }

    private func createSourceFiles(appDir: String, projectName: String, bundleIdPrefix: String)
        throws
    {
        // Create App.swift
        let appContent = """
            import SwiftUI

            @main
            struct \(projectName)App: App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }
            """
        try appContent.write(
            toFile: URL(fileURLWithPath: appDir).appendingPathComponent("\(projectName)App.swift")
                .path,
            atomically: true, encoding: .utf8)

        // Create ContentView.swift
        let contentViewContent = """
            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    VStack {
                        Image(systemName: "globe")
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                        Text("Hello, world!")
                    }
                    .padding()
                }
            }

            #Preview {
                ContentView()
            }
            """
        try contentViewContent.write(
            toFile: URL(fileURLWithPath: appDir).appendingPathComponent("ContentView.swift").path,
            atomically: true, encoding: .utf8)
    }

    private func createSwiftPackage(at path: String, packageName: String, deploymentTarget: String)
        throws
    {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)

        // Create Package.swift
        let packageContent = """
            // swift-tools-version: 5.9

            import PackageDescription

            let package = Package(
                name: "\(packageName)",
                platforms: [
                    .iOS(.v\(deploymentTarget.replacingOccurrences(of: ".", with: "_").prefix(2)))
                ],
                products: [
                    .library(
                        name: "\(packageName)",
                        targets: ["\(packageName)"]
                    ),
                ],
                targets: [
                    .target(
                        name: "\(packageName)"
                    ),
                    .testTarget(
                        name: "\(packageName)Tests",
                        dependencies: ["\(packageName)"]
                    ),
                ]
            )
            """
        try packageContent.write(
            toFile: URL(fileURLWithPath: path).appendingPathComponent("Package.swift").path,
            atomically: true, encoding: .utf8)

        // Create Sources directory
        let sourcesDir = URL(fileURLWithPath: path).appendingPathComponent("Sources/\(packageName)")
            .path
        try fileManager.createDirectory(atPath: sourcesDir, withIntermediateDirectories: true)

        let sourceContent = """
            import Foundation

            /// Shared utilities and models for \(packageName)
            public enum \(packageName) {
                public static let version = "1.0.0"
            }
            """
        try sourceContent.write(
            toFile: URL(fileURLWithPath: sourcesDir).appendingPathComponent("\(packageName).swift")
                .path,
            atomically: true, encoding: .utf8)

        // Create Tests directory
        let testsDir = URL(fileURLWithPath: path).appendingPathComponent(
            "Tests/\(packageName)Tests"
        ).path
        try fileManager.createDirectory(atPath: testsDir, withIntermediateDirectories: true)

        let testContent = """
            import Testing
            @testable import \(packageName)

            @Test func testVersion() {
                #expect(\(packageName).version == "1.0.0")
            }
            """
        try testContent.write(
            toFile: URL(fileURLWithPath: testsDir).appendingPathComponent(
                "\(packageName)Tests.swift"
            ).path,
            atomically: true, encoding: .utf8)
    }

    private func createTestFile(at testDir: String, projectName: String) throws {
        let content = """
            import Testing
            @testable import \(projectName)

            @Test func testExample() {
                // Add your test here
                #expect(true)
            }
            """
        try content.write(
            toFile: URL(fileURLWithPath: testDir).appendingPathComponent(
                "\(projectName)Tests.swift"
            ).path,
            atomically: true, encoding: .utf8)
    }

    private func createUITestFile(at uiTestDir: String, projectName: String) throws {
        let content = """
            import XCTest

            final class \(projectName)UITests: XCTestCase {
                override func setUpWithError() throws {
                    continueAfterFailure = false
                }

                func testLaunch() throws {
                    let app = XCUIApplication()
                    app.launch()

                    // Add your UI test assertions here
                }
            }
            """
        try content.write(
            toFile: URL(fileURLWithPath: uiTestDir).appendingPathComponent(
                "\(projectName)UITests.swift"
            ).path,
            atomically: true, encoding: .utf8)
    }
}
