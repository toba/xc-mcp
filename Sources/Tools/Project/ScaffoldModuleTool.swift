import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ScaffoldModuleTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "scaffold_module",
            description:
            "Create a framework module with optional test target, source folders, dependencies, and test plan entry — all in one call",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the framework module to create"),
                    ]),
                    "bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier for the framework (e.g. com.example.MyModule)",
                        ),
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Platform (iOS, macOS, tvOS, watchOS). Defaults to iOS",
                        ),
                    ]),
                    "deployment_target": .object([
                        "type": .string("string"),
                        "description": .string("Deployment target version (optional)"),
                    ]),
                    "parent_group": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Group to nest the module under (e.g. 'Modules' or 'Components/UI'). Defaults to project root",
                        ),
                    ]),
                    "source_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path for source files relative to project dir. Defaults to {parent_group}/{name}",
                        ),
                    ]),
                    "with_tests": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to create a unit test target. Defaults to true",
                        ),
                    ]),
                    "test_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path for test files relative to project dir. Defaults to {parent_group}/{name}Tests",
                        ),
                    ]),
                    "link_to": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Target names to link the framework into (adds dependency + Frameworks phase entry)",
                        ),
                    ]),
                    "embed_in": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Target names to embed the framework into (adds Embed Frameworks copy phase with CodeSignOnCopy)",
                        ),
                    ]),
                    "test_plan": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to .xctestplan file to add the test target to (optional)",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("name"), .string("bundle_identifier"),
                ]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        // 1. Extract and validate parameters
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(name) = arguments["name"],
              case let .string(bundleIdentifier) = arguments["bundle_identifier"]
        else {
            throw MCPError.invalidParams(
                "project_path, name, and bundle_identifier are required",
            )
        }

        let platform: String
        if case let .string(p) = arguments["platform"] {
            platform = p
        } else {
            platform = "iOS"
        }

        let deploymentTarget: String?
        if case let .string(dt) = arguments["deployment_target"] {
            deploymentTarget = dt
        } else {
            deploymentTarget = nil
        }

        let parentGroupPath: String?
        if case let .string(pg) = arguments["parent_group"] {
            parentGroupPath = pg
        } else {
            parentGroupPath = nil
        }

        let withTests: Bool
        if case let .bool(wt) = arguments["with_tests"] {
            withTests = wt
        } else {
            withTests = true
        }

        let linkToNames: [String]
        if case let .array(arr) = arguments["link_to"] {
            linkToNames = arr.compactMap { if case let .string(s) = $0 { s } else { nil } }
        } else {
            linkToNames = []
        }

        let embedInNames: [String]
        if case let .array(arr) = arguments["embed_in"] {
            embedInNames = arr.compactMap { if case let .string(s) = $0 { s } else { nil } }
        } else {
            embedInNames = []
        }

        let testPlanPath: String?
        if case let .string(tp) = arguments["test_plan"] {
            testPlanPath = tp
        } else {
            testPlanPath = nil
        }

        let testTargetName = "\(name)Tests"

        // Resolve project path
        let resolvedProjectPath: String
        let projectURL: URL
        do {
            resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            projectURL = URL(fileURLWithPath: resolvedProjectPath)
        }

        let projectDir = projectURL.deletingLastPathComponent().path

        // Compute source/test paths
        let parentPrefix = parentGroupPath.map { "\($0)/" } ?? ""

        let sourcePath: String
        if case let .string(sp) = arguments["source_path"] {
            sourcePath = sp
        } else {
            sourcePath = "\(parentPrefix)\(name)"
        }

        let testPath: String
        if case let .string(tp) = arguments["test_path"] {
            testPath = tp
        } else {
            testPath = "\(parentPrefix)\(testTargetName)"
        }

        // Absolute paths on disk
        let sourceAbsPath = (projectDir as NSString).appendingPathComponent(sourcePath)
        let testAbsPath = (projectDir as NSString).appendingPathComponent(testPath)

        // Track created directories for cleanup on failure
        var createdDirs: [String] = []

        do {
            // Load project once
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Validate no duplicate targets
            if xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == name }) {
                throw MCPError.invalidParams("Target '\(name)' already exists in project")
            }
            if withTests,
               xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == testTargetName })
            {
                throw MCPError.invalidParams(
                    "Target '\(testTargetName)' already exists in project",
                )
            }

            guard let project = xcodeproj.pbxproj.rootObject,
                  let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup
            else {
                throw MCPError.internalError("Cannot find project root or main group")
            }

            // Merge embed_in into link_to (embedding implies linking)
            let allLinkTargetNames = Array(Set(linkToNames + embedInNames))

            // Validate link_to / embed_in targets exist
            for targetName in allLinkTargetNames {
                if !xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == targetName }) {
                    throw MCPError.invalidParams(
                        "Target '\(targetName)' not found in project",
                    )
                }
            }

            // Introspect project configs
            let configNames: [String]
            if let projectConfigList = project.buildConfigurationList,
               !projectConfigList.buildConfigurations.isEmpty
            {
                configNames = projectConfigList.buildConfigurations.map(\.name)
            } else {
                configNames = ["Debug", "Release"]
            }

            // 2. Create directories on disk
            let fm = FileManager.default
            if !fm.fileExists(atPath: sourceAbsPath) {
                try fm.createDirectory(
                    atPath: sourceAbsPath, withIntermediateDirectories: true,
                )
                createdDirs.append(sourceAbsPath)
            }
            if withTests, !fm.fileExists(atPath: testAbsPath) {
                try fm.createDirectory(
                    atPath: testAbsPath, withIntermediateDirectories: true,
                )
                createdDirs.append(testAbsPath)
            }

            // 3. Create framework target
            let frameworkTarget = try createTarget(
                xcodeproj: xcodeproj,
                project: project,
                name: name,
                bundleIdentifier: bundleIdentifier,
                productType: .framework,
                platform: platform,
                deploymentTarget: deploymentTarget,
                configNames: configNames,
                extraSettings: ["DEFINES_MODULE": .string("YES")],
            )

            // 4. Create framework group + sync folder
            let containerGroup: PBXGroup
            if let parentGroupPath {
                containerGroup = try mainGroup.resolveGroupPath(parentGroupPath)
            } else {
                containerGroup = mainGroup
            }

            let frameworkGroup = PBXGroup(sourceTree: .group, name: name)
            xcodeproj.pbxproj.add(object: frameworkGroup)
            containerGroup.children.append(frameworkGroup)

            let frameworkSyncFolder = createSyncFolder(
                xcodeproj: xcodeproj,
                folderAbsPath: sourceAbsPath,
                containerGroup: frameworkGroup,
                projectRoot: projectDir,
                target: frameworkTarget,
            )

            // 5. Create test target (if with_tests)
            var testTarget: PBXNativeTarget?
            if withTests {
                let tt = try createTarget(
                    xcodeproj: xcodeproj,
                    project: project,
                    name: testTargetName,
                    bundleIdentifier: "\(bundleIdentifier)Tests",
                    productType: .unitTestBundle,
                    platform: platform,
                    deploymentTarget: deploymentTarget,
                    configNames: configNames,
                    extraSettings: [:],
                )
                testTarget = tt

                // Add dependency: test target depends on framework target
                addDependency(
                    xcodeproj: xcodeproj,
                    from: tt,
                    to: frameworkTarget,
                )

                // Link framework product into test target's Frameworks phase
                linkProduct(
                    xcodeproj: xcodeproj,
                    product: frameworkTarget.product!,
                    into: tt,
                )

                // 6. Create test group + sync folder
                let testGroup = PBXGroup(sourceTree: .group, name: testTargetName)
                xcodeproj.pbxproj.add(object: testGroup)
                containerGroup.children.append(testGroup)

                let testSyncFolder = createSyncFolder(
                    xcodeproj: xcodeproj,
                    folderAbsPath: testAbsPath,
                    containerGroup: testGroup,
                    projectRoot: projectDir,
                    target: tt,
                )
            }

            // 7. Wire link_to — add dependency + link framework
            for targetName in allLinkTargetNames {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else { continue }

                addDependency(
                    xcodeproj: xcodeproj,
                    from: target,
                    to: frameworkTarget,
                )

                linkProduct(
                    xcodeproj: xcodeproj,
                    product: frameworkTarget.product!,
                    into: target,
                )
            }

            // 8. Wire embed_in — find/create Embed Frameworks phase, add with CodeSignOnCopy
            for targetName in embedInNames {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else { continue }

                embedProduct(
                    xcodeproj: xcodeproj,
                    product: frameworkTarget.product!,
                    into: target,
                )
            }

            // 9. Add to test plan
            if let testPlanPath, withTests, let testTarget {
                let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)
                var json = try TestPlanFile.read(from: resolvedTestPlanPath)
                var testTargets = json["testTargets"] as? [[String: Any]] ?? []

                let existingNames = TestPlanFile.targetNames(from: json)
                if !existingNames.contains(testTargetName) {
                    let containerPath = TestPlanFile.containerPath(for: projectURL)
                    let entry: [String: Any] = [
                        "target": [
                            "containerPath": containerPath,
                            "identifier": testTarget.uuid,
                            "name": testTargetName,
                        ] as [String: Any],
                    ]
                    testTargets.append(entry)
                    json["testTargets"] = testTargets
                    try TestPlanFile.write(json, to: resolvedTestPlanPath)
                }
            }

            // 10. Write project — single write
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            // 11. Return summary
            var summary = [String]()
            summary.append("Created framework target '\(name)'")
            if withTests {
                summary.append("Created test target '\(testTargetName)'")
            }
            summary.append("Created source folder: \(sourcePath)")
            if withTests {
                summary.append("Created test folder: \(testPath)")
            }
            if !allLinkTargetNames.isEmpty {
                summary.append(
                    "Linked into: \(allLinkTargetNames.joined(separator: ", "))",
                )
            }
            if !embedInNames.isEmpty {
                summary.append(
                    "Embedded in: \(embedInNames.joined(separator: ", "))",
                )
            }
            if testPlanPath != nil, withTests {
                summary.append("Added '\(testTargetName)' to test plan")
            }

            return CallTool.Result(
                content: [.text(summary.joined(separator: "\n"))],
            )
        } catch let error as MCPError {
            // Clean up created directories on failure
            for dir in createdDirs.reversed() {
                try? FileManager.default.removeItem(atPath: dir)
            }
            throw error
        } catch {
            for dir in createdDirs.reversed() {
                try? FileManager.default.removeItem(atPath: dir)
            }
            throw MCPError.internalError(
                "Failed to scaffold module: \(error.localizedDescription)",
            )
        }
    }

    // MARK: - Helpers

    private func createTarget(
        xcodeproj: XcodeProj,
        project: PBXProject,
        name: String,
        bundleIdentifier: String,
        productType: PBXProductType,
        platform: String,
        deploymentTarget: String?,
        configNames: [String],
        extraSettings: [String: BuildSetting],
    ) -> PBXNativeTarget {
        var baseSettings: [String: BuildSetting] = [
            "PRODUCT_NAME": .string(name),
            "PRODUCT_BUNDLE_IDENTIFIER": .string(bundleIdentifier),
            "GENERATE_INFOPLIST_FILE": .string("YES"),
        ]
        for (key, value) in extraSettings {
            baseSettings[key] = value
        }

        // Add deployment target if specified
        if let deploymentTarget {
            let key =
                switch platform {
                    case "macOS": "MACOSX_DEPLOYMENT_TARGET"
                    case "tvOS": "TVOS_DEPLOYMENT_TARGET"
                    case "watchOS": "WATCHOS_DEPLOYMENT_TARGET"
                    default: "IPHONEOS_DEPLOYMENT_TARGET"
                }
            baseSettings[key] = .string(deploymentTarget)
        }

        var targetBuildConfigs: [XCBuildConfiguration] = []
        for configName in configNames {
            let config = XCBuildConfiguration(name: configName, buildSettings: baseSettings)
            xcodeproj.pbxproj.add(object: config)
            targetBuildConfigs.append(config)
        }

        let targetConfigurationList = XCConfigurationList(
            buildConfigurations: targetBuildConfigs,
            defaultConfigurationName: "Release",
        )
        xcodeproj.pbxproj.add(object: targetConfigurationList)

        let sourcesBuildPhase = PBXSourcesBuildPhase()
        xcodeproj.pbxproj.add(object: sourcesBuildPhase)

        let frameworksBuildPhase = PBXFrameworksBuildPhase()
        xcodeproj.pbxproj.add(object: frameworksBuildPhase)

        let resourcesBuildPhase = PBXResourcesBuildPhase()
        xcodeproj.pbxproj.add(object: resourcesBuildPhase)

        // Product reference
        let productName: String
        if let ext = productType.fileExtension {
            productName = "\(name).\(ext)"
        } else {
            productName = name
        }

        let productReference = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: productType.explicitFileType,
            path: productName,
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: productReference)

        let target = PBXNativeTarget(
            name: name,
            buildConfigurationList: targetConfigurationList,
            buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
            productType: productType,
        )
        target.productName = name
        target.product = productReference
        xcodeproj.pbxproj.add(object: target)

        project.targets.append(target)
        project.productsGroup?.children.append(productReference)

        return target
    }

    @discardableResult
    private func createSyncFolder(
        xcodeproj: XcodeProj,
        folderAbsPath: String,
        containerGroup: PBXGroup,
        projectRoot: String,
        target: PBXNativeTarget,
    ) -> PBXFileSystemSynchronizedRootGroup {
        let folderName = URL(fileURLWithPath: folderAbsPath).lastPathComponent

        // Calculate relative path from the container group
        let groupFullPath: String
        if let gp = try? containerGroup.fullPath(sourceRoot: projectRoot) {
            groupFullPath = gp
        } else {
            groupFullPath = projectRoot
        }

        let relativePath: String
        if folderAbsPath.hasPrefix(groupFullPath + "/") {
            relativePath = String(folderAbsPath.dropFirst(groupFullPath.count + 1))
        } else if folderAbsPath == groupFullPath {
            relativePath = "."
        } else {
            relativePath =
                pathUtility.makeRelativePath(from: folderAbsPath) ?? folderAbsPath
        }

        let folderReference = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group,
            path: relativePath,
            name: folderName,
        )
        xcodeproj.pbxproj.add(object: folderReference)
        containerGroup.children.append(folderReference)

        if target.fileSystemSynchronizedGroups == nil {
            target.fileSystemSynchronizedGroups = [folderReference]
        } else {
            target.fileSystemSynchronizedGroups?.append(folderReference)
        }

        return folderReference
    }

    private func addDependency(
        xcodeproj: XcodeProj,
        from dependent: PBXNativeTarget,
        to dependency: PBXNativeTarget,
    ) {
        // Skip if dependency already exists
        if dependent.dependencies.contains(where: { $0.target == dependency }) {
            return
        }

        let containerItemProxy = PBXContainerItemProxy(
            containerPortal: .project(xcodeproj.pbxproj.rootObject!),
            remoteGlobalID: .object(dependency),
            proxyType: .nativeTarget,
            remoteInfo: dependency.name,
        )
        xcodeproj.pbxproj.add(object: containerItemProxy)

        let targetDependency = PBXTargetDependency(
            name: dependency.name,
            target: dependency,
            targetProxy: containerItemProxy,
        )
        xcodeproj.pbxproj.add(object: targetDependency)

        dependent.dependencies.append(targetDependency)
    }

    private func linkProduct(
        xcodeproj: XcodeProj,
        product: PBXFileReference,
        into target: PBXNativeTarget,
    ) {
        // Find or create frameworks build phase
        let frameworksPhase: PBXFrameworksBuildPhase
        if let existing = target.buildPhases.first(
            where: { $0 is PBXFrameworksBuildPhase },
        ) as? PBXFrameworksBuildPhase {
            frameworksPhase = existing
        } else {
            let phase = PBXFrameworksBuildPhase()
            xcodeproj.pbxproj.add(object: phase)
            target.buildPhases.append(phase)
            frameworksPhase = phase
        }

        // Check if already linked
        let alreadyLinked = frameworksPhase.files?.contains { buildFile in
            buildFile.file === product
        } ?? false
        if alreadyLinked { return }

        let buildFile = PBXBuildFile(file: product)
        xcodeproj.pbxproj.add(object: buildFile)
        frameworksPhase.files?.append(buildFile)
    }

    private func embedProduct(
        xcodeproj: XcodeProj,
        product: PBXFileReference,
        into target: PBXNativeTarget,
    ) {
        // Find or create "Embed Frameworks" copy phase
        var embedPhase: PBXCopyFilesBuildPhase?
        for phase in target.buildPhases {
            if let copyPhase = phase as? PBXCopyFilesBuildPhase,
               copyPhase.dstSubfolderSpec == .frameworks || copyPhase.dstSubfolder == .frameworks
            {
                embedPhase = copyPhase
                break
            }
        }

        if embedPhase == nil {
            let phase = PBXCopyFilesBuildPhase(
                dstPath: "",
                dstSubfolderSpec: .frameworks,
                name: "Embed Frameworks",
            )
            xcodeproj.pbxproj.add(object: phase)
            target.buildPhases.append(phase)
            embedPhase = phase
        }

        // Check if already embedded
        let alreadyEmbedded = embedPhase?.files?.contains { $0.file === product } ?? false
        if alreadyEmbedded { return }

        let embedBuildFile = PBXBuildFile(
            file: product,
            settings: ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]],
        )
        xcodeproj.pbxproj.add(object: embedBuildFile)
        embedPhase?.files?.append(embedBuildFile)
    }
}
