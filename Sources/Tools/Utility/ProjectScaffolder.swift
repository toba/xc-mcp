import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// The platform a scaffolded app project targets
///
/// The two cases carry every value that differs between an iOS scaffold and a macOS scaffold.
/// ``ProjectScaffolder`` reads them and writes the same project layout for both.
public enum ScaffoldPlatform: Sendable {
    case iOS
    case macOS

    /// The platform the generated build settings name.
    public var platform: ApplePlatform {
        switch self {
            case .iOS: .iOS
            case .macOS: .macOS
        }
    }

    /// The MCP tool name that scaffolds this platform.
    var toolName: String {
        switch self {
            case .iOS: "scaffold_ios_project"
            case .macOS: "scaffold_macos_project"
        }
    }

    /// The minimum OS version applied when the caller omits `deployment_target`.
    var defaultDeploymentTarget: String {
        switch self {
            case .iOS: "17.0"
            case .macOS: "14.0"
        }
    }

    /// A lower version than ``defaultDeploymentTarget``, shown in the schema description.
    var exampleDeploymentTarget: String {
        switch self {
            case .iOS: "16.0"
            case .macOS: "13.0"
        }
    }

    /// The `LD_RUNPATH_SEARCH_PATHS` value for an app bundle on this platform.
    ///
    /// A macOS bundle nests the executable one level deeper than an iOS bundle does.
    var runpathSearchPaths: String {
        switch self {
            case .iOS: "$(inherited) @executable_path/Frameworks"
            case .macOS: "$(inherited) @executable_path/../Frameworks"
        }
    }

    /// Whether the app target signs with an entitlements file the scaffold writes.
    var writesEntitlements: Bool {
        switch self {
            case .iOS: false
            case .macOS: true
        }
    }

    /// Build settings the app target carries on this platform alone.
    ///
    /// - Parameter productName: The target name, used to place the entitlements file.
    func exclusiveAppTargetSettings(productName: String) -> BuildSettings {
        switch self {
            case .iOS:
                [
                    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": .string("YES"),
                    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": .string("YES"),
                    "INFOPLIST_KEY_UILaunchScreen_Generation": .string("YES"),
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
                        .string(
                            "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                        ),
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
                        .string(
                            "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                        ),
                ]
            case .macOS:
                [
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": .string("AccentColor"),
                    "CODE_SIGN_ENTITLEMENTS": .string("\(productName)/\(productName).entitlements"),
                    "COMBINE_HIDPI_IMAGES": .string("YES"),
                    "ENABLE_HARDENED_RUNTIME": .string("YES"),
                    "INFOPLIST_KEY_NSHumanReadableCopyright": .string(""),
                    "INFOPLIST_KEY_NSPrincipalClass": .string("NSApplication"),
                ]
        }
    }

    /// The `images` array of the generated `AppIcon.appiconset` manifest.
    var appIconImages: String {
        switch self {
            case .iOS:
                """
                    {
                      "idiom" : "universal",
                      "platform" : "ios",
                      "size" : "1024x1024"
                    }
                """
            case .macOS: Self.macAppIconImages
        }
    }

    /// The ten mac icon entries, five sizes at two scales each.
    private static let macAppIconImages: String = {
        let sizes = ["16x16", "32x32", "128x128", "256x256", "512x512"]
        let entries = sizes.flatMap { size in
            ["1x", "2x"].map { scale in
                """
                    {
                      "idiom" : "mac",
                      "scale" : "\(scale)",
                      "size" : "\(size)"
                    }
                """
            }
        }
        return entries.joined(separator: ",\n")
    }()
}

/// Creates a workspace, an Xcode project and a companion Swift package for a new app
///
/// The generated app source folder is a synchronized root group, so Xcode picks up files dropped on
/// disk with no project edit. `scaffold_ios_project` and `scaffold_macos_project` both run through
/// this type and differ only by their ``ScaffoldPlatform``.
public struct ProjectScaffolder: Sendable {
    private let scaffoldPlatform: ScaffoldPlatform
    private let pathUtility: PathUtility

    public init(platform: ScaffoldPlatform, pathUtility: PathUtility) {
        scaffoldPlatform = platform
        self.pathUtility = pathUtility
    }

    private var platform: ApplePlatform { scaffoldPlatform.platform }

    public func tool() -> Tool {
        .init(
            name: scaffoldPlatform.toolName,
            description:
                "Create a new \(platform.rawValue) project with a modern workspace + Swift Package Manager architecture. The app source folder is a synchronized root group (Xcode 16+), so files dropped on disk are picked up automatically — no add_file needed.",
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
                            "Bundle identifier prefix (e.g., com.example). The app will use this prefix + project name.",
                        ),
                    ]),
                    "deployment_target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Minimum \(platform.rawValue) version to support (e.g., '\(scaffoldPlatform.exampleDeploymentTarget)'). Defaults to '\(scaffoldPlatform.defaultDeploymentTarget)'.",
                        ),
                    ]),
                    "include_tests": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include unit test and UI test targets. Defaults to true.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_name"), .string("path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let projectName = try arguments.getRequiredString("project_name")
        let basePath = try arguments.getRequiredString("path")
        let organizationName = arguments.getString("organization_name") ?? "Organization"
        let bundleIDPrefix = arguments.getString("bundle_identifier") ?? "com.example"
        let deploymentTarget = arguments.getString("deployment_target")
            ?? scaffoldPlatform.defaultDeploymentTarget
        let includeTests = arguments.getBool("include_tests", default: true)

        let resolvedBasePath = try pathUtility.resolvePath(from: basePath)

        let projectDir = URL(fileURLWithPath: resolvedBasePath).appendingPathComponent(projectName)
            .path
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: projectDir) {
            throw MCPError.invalidParams("Directory already exists: \(projectDir)")
        }

        do {
            try fileManager.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

            let appDir = URL(fileURLWithPath: projectDir).appendingPathComponent(projectName).path
            try fileManager.createDirectory(atPath: appDir, withIntermediateDirectories: true)

            let projectPath = URL(fileURLWithPath: projectDir).appendingPathComponent(
                "\(projectName).xcodeproj",
            ).path
            let pbxproj = PBXProj()
            let project = createProject(
                pbxproj: pbxproj,
                projectName: projectName,
                organizationName: organizationName,
                bundleIDPrefix: bundleIDPrefix,
                deploymentTarget: deploymentTarget,
            )
            pbxproj.add(object: project)
            pbxproj.rootObject = project

            let workspaceData = XCWorkspaceData(children: [])
            let workspace = XCWorkspace(data: workspaceData)
            let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
            try xcodeproj.write(path: Path(projectPath))

            let workspacePath = URL(fileURLWithPath: projectDir).appendingPathComponent(
                "\(projectName).xcworkspace",
            ).path
            try createWorkspace(at: workspacePath, projectName: projectName)

            try createSourceFiles(appDir: appDir, projectName: projectName)
            try createAssetCatalog(appDir: appDir)

            let packageDir = URL(fileURLWithPath: projectDir).appendingPathComponent(
                "\(projectName)Kit",
            ).path
            try createSwiftPackage(
                at: packageDir, packageName: "\(projectName)Kit",
                deploymentTarget: deploymentTarget,
            )

            if includeTests {
                let testDir = URL(fileURLWithPath: projectDir).appendingPathComponent(
                    "\(projectName)Tests",
                ).path
                try fileManager.createDirectory(atPath: testDir, withIntermediateDirectories: true)
                try createTestFile(at: testDir, projectName: projectName)

                let uiTestDir = URL(fileURLWithPath: projectDir).appendingPathComponent(
                    "\(projectName)UITests",
                ).path
                try fileManager.createDirectory(
                    atPath: uiTestDir, withIntermediateDirectories: true,
                )
                try createUITestFile(at: uiTestDir, projectName: projectName)
            }

            var resultMessage =
                "Successfully created \(platform.rawValue) project '\(projectName)' at \(projectDir)\n\n"
            resultMessage += "Created:\n"
            resultMessage += "  - \(projectName).xcworkspace (workspace)\n"
            resultMessage += "  - \(projectName).xcodeproj (Xcode project)\n"
            resultMessage += "  - \(projectName)/ (app sources + asset catalog)\n"
            resultMessage += "  - \(projectName)Kit/ (Swift package for shared code)\n"

            if includeTests {
                resultMessage += "  - \(projectName)Tests/ (unit tests)\n"
                resultMessage += "  - \(projectName)UITests/ (UI tests)\n"
            }
            resultMessage += "\nOpen the workspace with: open \"\(workspacePath)\""

            return CallTool.Result.text(resultMessage)
        } catch {
            // clean up a half-written project
            try? fileManager.removeItem(atPath: projectDir)
            throw try error.asMCPError()
        }
    }

    private func createProject(
        pbxproj: PBXProj,
        projectName: String,
        organizationName: String,
        bundleIDPrefix: String,
        deploymentTarget: String,
    ) -> PBXProject {
        let mainGroup = PBXGroup(children: [], sourceTree: .group)
        pbxproj.add(object: mainGroup)

        let debugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: createProjectBuildSettings(
                debug: true, deploymentTarget: deploymentTarget,
            ),
        )
        let releaseConfig = XCBuildConfiguration(
            name: "Release",
            buildSettings: createProjectBuildSettings(
                debug: false, deploymentTarget: deploymentTarget,
            ),
        )
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)

        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: configList)

        let project = PBXProject(
            name: projectName,
            buildConfigurationList: configList,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: 77,
            minimizedProjectReferenceProxies: 0,
            mainGroup: mainGroup,
            developmentRegion: "en",
            attributes: ["ORGANIZATIONNAME": .string(organizationName)],
        )

        let appTarget = createAppTarget(
            pbxproj: pbxproj,
            projectName: projectName,
            bundleIDPrefix: bundleIDPrefix,
            deploymentTarget: deploymentTarget,
            mainGroup: mainGroup,
        )
        project.targets.append(appTarget)

        return project
    }

    private func createAppTarget(
        pbxproj: PBXProj,
        projectName: String,
        bundleIDPrefix: String,
        deploymentTarget: String,
        mainGroup: PBXGroup,
    ) -> PBXNativeTarget {
        // Synchronized root group: Xcode auto-discovers all files in the folder.
        let appFolder = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group,
            path: projectName,
            name: projectName,
        )
        pbxproj.add(object: appFolder)
        mainGroup.children.append(appFolder)

        let sourcesBuildPhase = PBXSourcesBuildPhase(files: [])
        pbxproj.add(object: sourcesBuildPhase)

        let frameworksBuildPhase = PBXFrameworksBuildPhase(files: [])
        pbxproj.add(object: frameworksBuildPhase)

        let resourcesBuildPhase = PBXResourcesBuildPhase(files: [])
        pbxproj.add(object: resourcesBuildPhase)

        let bundleID = "\(bundleIDPrefix).\(projectName)"
        let debugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: createAppTargetBuildSettings(
                debug: true,
                productName: projectName,
                bundleID: bundleID,
                deploymentTarget: deploymentTarget,
            ),
        )
        let releaseConfig = XCBuildConfiguration(
            name: "Release",
            buildSettings: createAppTargetBuildSettings(
                debug: false,
                productName: projectName,
                bundleID: bundleID,
                deploymentTarget: deploymentTarget,
            ),
        )
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)

        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: configList)

        let target = PBXNativeTarget(
            name: projectName,
            buildConfigurationList: configList,
            buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
            productType: .application,
        )
        pbxproj.add(object: target)
        target.fileSystemSynchronizedGroups = [appFolder]

        return target
    }

    private func createProjectBuildSettings(
        debug: Bool,
        deploymentTarget: String,
    ) -> BuildSettings {
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
            "MTL_ENABLE_DEBUG_INFO": .string(debug ? "INCLUDE_SOURCE" : "NO"),
            "SDKROOT": .string(platform.sdkRoot),
            "SWIFT_VERSION": .string("5.0"),
            platform.deploymentTargetKey: .string(deploymentTarget),
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
        bundleID: String,
        deploymentTarget: String,
    ) -> BuildSettings {
        var settings: BuildSettings = [
            "ASSETCATALOG_COMPILER_APPICON_NAME": .string("AppIcon"),
            "CODE_SIGN_STYLE": .string("Automatic"),
            "CURRENT_PROJECT_VERSION": .string("1"),
            "GENERATE_INFOPLIST_FILE": .string("YES"),
            "LD_RUNPATH_SEARCH_PATHS": .string(scaffoldPlatform.runpathSearchPaths),
            "MARKETING_VERSION": .string("1.0"),
            "PRODUCT_BUNDLE_IDENTIFIER": .string(bundleID),
            "PRODUCT_NAME": .string("$(TARGET_NAME)"),
            "SWIFT_EMIT_LOC_STRINGS": .string("YES"),
            platform.deploymentTargetKey: .string(deploymentTarget),
        ]

        if let deviceFamily = platform.targetedDeviceFamily {
            settings["TARGETED_DEVICE_FAMILY"] = .string(deviceFamily)
        }

        for (key, value) in scaffoldPlatform.exclusiveAppTargetSettings(productName: productName) {
            settings[key] = value
        }

        if debug {
            settings["SWIFT_OPTIMIZATION_LEVEL"] = .string("-Onone")
            settings["ONLY_ACTIVE_ARCH"] = .string("YES")
        }

        return settings
    }

    private func createWorkspace(at path: String, projectName: String) throws {
        let workspaceDataPath = URL(fileURLWithPath: path).appendingPathComponent(
            "contents.xcworkspacedata",
        ).path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

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

    private func createSourceFiles(appDir: String, projectName: String) throws {
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
            atomically: true, encoding: .utf8,
        )

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
            atomically: true, encoding: .utf8,
        )

        guard scaffoldPlatform.writesEntitlements else { return }

        let entitlementsContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>com.apple.security.app-sandbox</key>
                <true/>
            </dict>
            </plist>
            """
        try entitlementsContent.write(
            toFile: URL(fileURLWithPath: appDir).appendingPathComponent(
                "\(projectName).entitlements",
            ).path,
            atomically: true, encoding: .utf8,
        )
    }

    private func createAssetCatalog(appDir: String) throws {
        let fileManager = FileManager.default
        let assetsDir = URL(fileURLWithPath: appDir).appendingPathComponent("Assets.xcassets").path

        try fileManager.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)
        try """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """.write(
            toFile: URL(fileURLWithPath: assetsDir).appendingPathComponent("Contents.json").path,
            atomically: true, encoding: .utf8,
        )

        let accentDir = URL(fileURLWithPath: assetsDir).appendingPathComponent(
            "AccentColor.colorset",
        ).path
        try fileManager.createDirectory(atPath: accentDir, withIntermediateDirectories: true)
        try """
        {
          "colors" : [
            {
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """.write(
            toFile: URL(fileURLWithPath: accentDir).appendingPathComponent("Contents.json").path,
            atomically: true, encoding: .utf8,
        )

        let iconDir = URL(fileURLWithPath: assetsDir).appendingPathComponent("AppIcon.appiconset")
            .path
        try fileManager.createDirectory(atPath: iconDir, withIntermediateDirectories: true)
        try """
        {
          "images" : [
        \(scaffoldPlatform.appIconImages)
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """.write(
            toFile: URL(fileURLWithPath: iconDir).appendingPathComponent("Contents.json").path,
            atomically: true, encoding: .utf8,
        )
    }

    private func createSwiftPackage(
        at path: String,
        packageName: String,
        deploymentTarget: String,
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)

        let majorVersion = deploymentTarget.replacingOccurrences(of: ".", with: "_").prefix(2)
        let packageContent = """
            // swift-tools-version: 5.9

            import PackageDescription

            let package = Package(
                name: "\(packageName)",
                platforms: [
                    .\(platform.rawValue)(.v\(majorVersion))
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
            atomically: true, encoding: .utf8,
        )

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
            atomically: true, encoding: .utf8,
        )

        let testsDir = URL(fileURLWithPath: path).appendingPathComponent(
            "Tests/\(packageName)Tests",
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
                "\(packageName)Tests.swift",
            ).path,
            atomically: true, encoding: .utf8,
        )
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
                "\(projectName)Tests.swift",
            ).path,
            atomically: true, encoding: .utf8,
        )
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
                "\(projectName)UITests.swift",
            ).path,
            atomically: true, encoding: .utf8,
        )
    }
}
