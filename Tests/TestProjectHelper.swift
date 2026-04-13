import MCP
import PathKit
import XcodeProj
import Foundation

enum TestProjectHelper {
    static func createTestProject(name: String, at path: Path) throws {
        // Create the .pbxproj file using XcodeProj
        let pbxproj = PBXProj()

        // Create project groups
        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)
        let testsGroup = PBXGroup(children: [], sourceTree: .group, path: "Tests")
        pbxproj.add(object: testsGroup)
        mainGroup.children.append(testsGroup)

        // Create build configurations
        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)

        // Create configuration list
        let configurationList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: configurationList)

        // Create project
        let project = PBXProject(
            name: name,
            buildConfigurationList: configurationList,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: 77,
            minimizedProjectReferenceProxies: 0,
            mainGroup: mainGroup,
            developmentRegion: "en",
            knownRegions: ["en", "Base"],
            productsGroup: productsGroup,
        )
        pbxproj.add(object: project)
        pbxproj.rootObject = project

        // Create workspace
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)

        // Create xcodeproj
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)

        // Write project
        try xcodeproj.write(path: path)
    }

    static func createTestProjectWithTarget(
        name: String,
        targetName: String,
        at path: Path,
    ) throws {
        // Create the .pbxproj file using XcodeProj
        let pbxproj = PBXProj()

        // Create project groups
        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        // Create build configurations for project
        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)

        // Create configuration list for project
        let configurationList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: configurationList)

        // Create target build configurations
        let targetDebugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: [
                "PRODUCT_NAME": .string(targetName),
                "BUNDLE_IDENTIFIER": .string("com.example.\(targetName)"),
            ],
        )
        let targetReleaseConfig = XCBuildConfiguration(
            name: "Release",
            buildSettings: [
                "PRODUCT_NAME": .string(targetName),
                "BUNDLE_IDENTIFIER": .string("com.example.\(targetName)"),
            ],
        )
        pbxproj.add(object: targetDebugConfig)
        pbxproj.add(object: targetReleaseConfig)

        // Create target configuration list
        let targetConfigurationList = XCConfigurationList(
            buildConfigurations: [targetDebugConfig, targetReleaseConfig],
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: targetConfigurationList)

        // Create build phases
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        pbxproj.add(object: sourcesBuildPhase)

        let resourcesBuildPhase = PBXResourcesBuildPhase()
        pbxproj.add(object: resourcesBuildPhase)

        // Create target
        let target = PBXNativeTarget(
            name: targetName,
            buildConfigurationList: targetConfigurationList,
            buildPhases: [sourcesBuildPhase, resourcesBuildPhase],
            productType: .application,
        )
        pbxproj.add(object: target)

        // Create project
        let project = PBXProject(
            name: name,
            buildConfigurationList: configurationList,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: 77,
            minimizedProjectReferenceProxies: 0,
            mainGroup: mainGroup,
            developmentRegion: "en",
            knownRegions: ["en", "Base"],
            productsGroup: productsGroup,
            targets: [target],
        )
        pbxproj.add(object: project)
        pbxproj.rootObject = project

        // Create workspace
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)

        // Create xcodeproj
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)

        // Write project
        try xcodeproj.write(path: path)
    }

    /// Creates a test project with two native targets.
    static func createTestProjectWithTwoTargets(
        name: String,
        target1: String,
        target2: String,
        at path: Path,
    ) throws {
        let pbxproj = PBXProj()

        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)

        let configurationList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: configurationList)

        func makeTarget(_ targetName: String) -> PBXNativeTarget {
            let tDebug = XCBuildConfiguration(
                name: "Debug",
                buildSettings: [
                    "PRODUCT_NAME": .string(targetName),
                    "BUNDLE_IDENTIFIER": .string("com.example.\(targetName)"),
                ],
            )
            let tRelease = XCBuildConfiguration(
                name: "Release",
                buildSettings: [
                    "PRODUCT_NAME": .string(targetName),
                    "BUNDLE_IDENTIFIER": .string("com.example.\(targetName)"),
                ],
            )
            pbxproj.add(object: tDebug)
            pbxproj.add(object: tRelease)

            let tConfigList = XCConfigurationList(
                buildConfigurations: [tDebug, tRelease],
                defaultConfigurationName: "Release",
            )
            pbxproj.add(object: tConfigList)

            let sources = PBXSourcesBuildPhase()
            pbxproj.add(object: sources)
            let resources = PBXResourcesBuildPhase()
            pbxproj.add(object: resources)

            let target = PBXNativeTarget(
                name: targetName,
                buildConfigurationList: tConfigList,
                buildPhases: [sources, resources],
                productType: .application,
            )
            pbxproj.add(object: target)
            return target
        }

        let t1 = makeTarget(target1)
        let t2 = makeTarget(target2)

        let project = PBXProject(
            name: name,
            buildConfigurationList: configurationList,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: 77,
            minimizedProjectReferenceProxies: 0,
            mainGroup: mainGroup,
            developmentRegion: "en",
            knownRegions: ["en", "Base"],
            productsGroup: productsGroup,
            targets: [t1, t2],
        )
        pbxproj.add(object: project)
        pbxproj.rootObject = project

        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: path)
    }

    /// Creates a test project with a target whose build phases have `files = nil`.
    ///
    /// This simulates real-world Xcode projects where a build phase exists but has
    /// never had files added (Xcode omits the `files` key, so XcodeProj reads it as nil).
    static func createTestProjectWithNilPhaseFiles(
        name: String,
        targetName: String,
        at path: Path,
    ) throws {
        try createTestProjectWithTarget(name: name, targetName: targetName, at: path)

        let xcodeproj = try XcodeProj(path: path)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == targetName }!
        for phase in target.buildPhases {
            if let sources = phase as? PBXSourcesBuildPhase {
                sources.files = nil
            } else if let resources = phase as? PBXResourcesBuildPhase {
                resources.files = nil
            } else if let headers = phase as? PBXHeadersBuildPhase {
                headers.files = nil
            }
        }
        try xcodeproj.write(path: path)
    }

    /// Creates a test project with a target and a synchronized folder, optionally with an exception set.
    static func createTestProjectWithSyncFolder(
        name: String,
        targetName: String,
        folderPath: String,
        membershipExceptions: [String]? = nil,
        at path: Path,
    ) throws {
        try createTestProjectWithTarget(name: name, targetName: targetName, at: path)

        let xcodeproj = try XcodeProj(path: path)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: folderPath, name: folderPath,
        )
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }

        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == targetName }!
        target.fileSystemSynchronizedGroups = [syncGroup]

        if let exceptions = membershipExceptions {
            let exceptionSet = PBXFileSystemSynchronizedBuildFileExceptionSet(
                target: target,
                membershipExceptions: exceptions,
                publicHeaders: nil,
                privateHeaders: nil,
                additionalCompilerFlagsByRelativePath: nil,
                attributesByRelativePath: nil,
            )
            xcodeproj.pbxproj.add(object: exceptionSet)
            syncGroup.exceptions = [exceptionSet]
        }

        try xcodeproj.write(path: path)
    }
}
