import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for package requirement tests
struct PackageRequirementTestCase {
    let packageUrl: String
    let requirementInput: String
    let expectedRequirementDescription: String

    init(_ packageUrl: String, _ requirementInput: String, _ expectedDescription: String) {
        self.packageUrl = packageUrl
        self.requirementInput = requirementInput
        expectedRequirementDescription = expectedDescription
    }
}

/// Test case for missing parameter validation
struct SwiftPackageMissingParamTestCase {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

struct AddSwiftPackageToolTests {
    @Test
    func `Tool creation`() {
        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_swift_package")
        #expect(
            toolDefinition.description
                == "Add a Swift Package dependency to an Xcode project (remote URL or local path)",
        )
    }

    static let missingParamCases: [SwiftPackageMissingParamTestCase] = [
        SwiftPackageMissingParamTestCase(
            "Missing project_path",
            [
                "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
                "requirement": Value.string("5.0.0"),
            ],
        ),
        SwiftPackageMissingParamTestCase(
            "Missing package_url",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "requirement": Value.string("5.0.0"),
            ],
        ),
        SwiftPackageMissingParamTestCase(
            "Missing requirement",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
            ],
        ),
    ]

    @Test(arguments: missingParamCases)
    func `Add package with missing parameters`(_ testCase: SwiftPackageMissingParamTestCase) throws {
        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    static let requirementCases: [PackageRequirementTestCase] = [
        PackageRequirementTestCase(
            "https://github.com/alamofire/alamofire.git",
            "5.0.0",
            #"exact("5.0.0")"#,
        ),
        PackageRequirementTestCase(
            "https://github.com/pointfreeco/swift-composable-architecture.git",
            "from: 1.0.0",
            #"upToNextMajorVersion("1.0.0")"#,
        ),
        PackageRequirementTestCase(
            "https://github.com/apple/swift-algorithms.git",
            "branch: main",
            #"branch("main")"#,
        ),
    ]

    @Test(arguments: requirementCases)
    func `Add Swift Package with requirement`(_ testCase: PackageRequirementTestCase) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string(testCase.packageUrl),
            "requirement": Value.string(testCase.requirementInput),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added Swift Package"))

        // Verify package was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let packageRef = project?.remotePackages.first {
            $0.repositoryURL == testCase.packageUrl
        }
        #expect(packageRef != nil)

        // Verify the requirement matches expected description
        if let requirement = packageRef?.versionRequirement {
            let requirementDescription = String(describing: requirement)
            #expect(requirementDescription == testCase.expectedRequirementDescription)
        } else {
            Issue.record("Expected version requirement")
        }
    }

    @Test
    func `Add Swift Package to specific target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/realm/realm-swift.git"),
            "requirement": Value.string("10.0.0"),
            "target_name": Value.string("TestApp"),
            "product_name": Value.string("RealmSwift"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added Swift Package"))
        #expect(message.contains("to target 'TestApp'"))

        // Verify package was added and linked to target
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let packageRef = project?.remotePackages.first {
            $0.repositoryURL == "https://github.com/realm/realm-swift.git"
        }
        #expect(packageRef != nil)

        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target != nil)
        #expect(target?.packageProductDependencies?.count == 1)
    }

    @Test
    func `Add duplicate Swift Package`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
        ]

        // Add package first time
        _ = try tool.execute(arguments: args)

        // Try to add same package again
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test
    func `Add local Swift Package`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string("../MyLocalPackage"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added local Swift Package"))
        #expect(message.contains("../MyLocalPackage"))

        // Verify package was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try xcodeproj.pbxproj.rootProject()
        let localRef = project?.localPackages.first {
            $0.relativePath == "../MyLocalPackage"
        }
        #expect(localRef != nil)
    }

    @Test
    func `Add duplicate local Swift Package`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string("../MyLocalPackage"),
        ]

        // Add package first time
        _ = try tool.execute(arguments: args)

        // Try to add same package again
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test
    func `Add local Swift Package to specific target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string("../SharedKit"),
            "target_name": Value.string("TestApp"),
            "product_name": Value.string("SharedKit"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added local Swift Package"))
        #expect(message.contains("to target 'TestApp'"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target?.packageProductDependencies?.count == 1)
    }

    @Test
    func `Add Swift Package to target adds PBXBuildFile to Frameworks build phase`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string("../SharedKit"),
            "target_name": Value.string("TestApp"),
            "product_name": Value.string("SharedKit"),
        ]

        _ = try tool.execute(arguments: args)

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }

        // Verify a Frameworks build phase was created with a build file referencing the package product
        let frameworkPhase =
            target?.buildPhases.first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase
        #expect(frameworkPhase != nil, "Target should have a Frameworks build phase")

        let hasPackageBuildFile = frameworkPhase?.files?.contains { buildFile in
            buildFile.product?.productName == "SharedKit"
        } ?? false
        #expect(
            hasPackageBuildFile,
            "Frameworks build phase should contain a build file for the package product",
        )
    }

    @Test
    func `Existing remote package links product to new target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "ExtTarget", at: projectPath,
        )

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

        // Add package to first target
        let args1: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("AppTarget"),
            "product_name": Value.string("Collections"),
        ]
        let result1 = try tool.execute(arguments: args1)
        guard case let .text(msg1, _, _) = result1.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(msg1.contains("Successfully added"))

        // Add same package to second target
        let args2: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("ExtTarget"),
            "product_name": Value.string("Collections"),
        ]
        let result2 = try tool.execute(arguments: args2)
        guard case let .text(msg2, _, _) = result2.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(msg2.contains("already in project"))
        #expect(msg2.contains("linked product"))
        #expect(msg2.contains("ExtTarget"))

        // Verify both targets have the product linked
        let xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTarget" }
        let extTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "ExtTarget" }
        #expect(appTarget?.packageProductDependencies?.count == 1)
        #expect(extTarget?.packageProductDependencies?.count == 1)

        // Verify only one package reference exists
        let project = try xcodeproj.pbxproj.rootProject()
        let refs = project?.remotePackages.filter {
            $0.repositoryURL == "https://github.com/apple/swift-collections.git"
        }
        #expect(refs?.count == 1)
    }

    @Test
    func `Existing local package links product to new target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "ExtTarget", at: projectPath,
        )

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

        // Add local package to first target
        let args1: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string("../SharedKit"),
            "target_name": Value.string("AppTarget"),
            "product_name": Value.string("SharedKit"),
        ]
        _ = try tool.execute(arguments: args1)

        // Add same local package to second target
        let args2: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string("../SharedKit"),
            "target_name": Value.string("ExtTarget"),
            "product_name": Value.string("SharedKit"),
        ]
        let result2 = try tool.execute(arguments: args2)
        guard case let .text(msg2, _, _) = result2.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(msg2.contains("already in project"))
        #expect(msg2.contains("linked product"))
        #expect(msg2.contains("ExtTarget"))

        // Verify both targets have the product linked
        let xcodeproj = try XcodeProj(path: projectPath)
        let extTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "ExtTarget" }
        #expect(extTarget?.packageProductDependencies?.count == 1)
    }

    @Test
    func `Existing local package at parent dir links product to second target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "SwiftiomaticApp", target2: "SwiftiomaticExtension",
            at: projectPath,
        )

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

        // Step 1: Add local package ".." to extension target (first-time add, should succeed)
        let args1: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string(".."),
            "target_name": Value.string("SwiftiomaticExtension"),
            "product_name": Value.string("SwiftiomaticLib"),
        ]
        let result1 = try tool.execute(arguments: args1)
        guard case let .text(msg1, _, _) = result1.content.first else {
            Issue.record("Expected text result for first add")
            return
        }
        #expect(msg1.contains("Successfully added local Swift Package"))

        // Step 2: Link same package to app target (package exists, should still link)
        let args2: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_path": Value.string(".."),
            "target_name": Value.string("SwiftiomaticApp"),
            "product_name": Value.string("SwiftiomaticLib"),
        ]
        let result2 = try tool.execute(arguments: args2)
        guard case let .text(msg2, _, _) = result2.content.first else {
            Issue.record("Expected text result for second add")
            return
        }

        // MUST NOT return the bare "already exists" message
        #expect(!msg2.contains("already exists in project"))
        // MUST confirm the product was linked
        #expect(msg2.contains("linked product"))
        #expect(msg2.contains("SwiftiomaticApp"))

        // Verify both targets have the product dependency
        let xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "SwiftiomaticApp" }
        let extTarget = xcodeproj.pbxproj.nativeTargets.first {
            $0.name == "SwiftiomaticExtension"
        }
        #expect(appTarget?.packageProductDependencies?.count == 1)
        #expect(extTarget?.packageProductDependencies?.count == 1)

        // Verify only one local package reference exists (not duplicated)
        let project = try xcodeproj.pbxproj.rootProject()
        let localRefs = project?.localPackages.filter { $0.relativePath == ".." }
        #expect(localRefs?.count == 1)

        // Verify both targets have a Frameworks build phase with the product
        for targetName in ["SwiftiomaticApp", "SwiftiomaticExtension"] {
            let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == targetName }
            let fwPhase = target?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                as? PBXFrameworksBuildPhase
            #expect(fwPhase != nil, "\(targetName) should have a Frameworks build phase")
            let hasBuildFile =
                fwPhase?.files?.contains { $0.product?.productName == "SwiftiomaticLib" }
                    ?? false
            #expect(hasBuildFile, "\(targetName) Frameworks phase should reference SwiftiomaticLib")
        }
    }

    @Test
    func `Existing package rejects duplicate product link to same target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

        // Add package to target
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("TestApp"),
            "product_name": Value.string("Collections"),
        ]
        _ = try tool.execute(arguments: args)

        // Try to link same product to same target again
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test
    func `Add package fails with both URL and path`() throws {
        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))
        let args: [String: Value] = [
            "project_path": Value.string("/path/to/project.xcodeproj"),
            "package_url": Value.string("https://github.com/example/repo.git"),
            "package_path": Value.string("../LocalPackage"),
            "requirement": Value.string("1.0.0"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test
    func `Add package fails with neither URL nor path`() throws {
        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))
        let args: [String: Value] = [
            "project_path": Value.string("/path/to/project.xcodeproj"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    /// Reproducer for issue 2fi-f1h: add_swift_package crashes with SIGTRAP when the project
    /// already has existing SPM packages (like the Thesis project with 5 remote + 1 local).
    @Test
    func `Add package to project with existing packages`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "Core", at: projectPath,
        )

        // Pre-populate with existing SPM packages (simulating Thesis-like project)
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try #require(try xcodeproj.pbxproj.rootProject())
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "Core" })

        let existingPackages: [(url: String, version: String, product: String)] = [
            ("https://github.com/apple/swift-collections.git", "1.1.0", "Collections"),
            ("https://github.com/apple/swift-async-algorithms.git", "1.0.0", "AsyncAlgorithms"),
            ("https://github.com/apple/swift-log.git", "1.5.0", "Logging"),
        ]

        for pkg in existingPackages {
            let pkgRef = XCRemoteSwiftPackageReference(
                repositoryURL: pkg.url,
                versionRequirement: .upToNextMajorVersion(pkg.version),
            )
            xcodeproj.pbxproj.add(object: pkgRef)
            project.remotePackages.append(pkgRef)

            let productDep = XCSwiftPackageProductDependency(
                productName: pkg.product, package: pkgRef,
            )
            xcodeproj.pbxproj.add(object: productDep)
            if target.packageProductDependencies == nil {
                target.packageProductDependencies = []
            }
            target.packageProductDependencies?.append(productDep)

            let buildFile = PBXBuildFile(product: productDep)
            xcodeproj.pbxproj.add(object: buildFile)

            let fwPhase = target.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                as? PBXFrameworksBuildPhase
                ?? {
                    let phase = PBXFrameworksBuildPhase()
                    xcodeproj.pbxproj.add(object: phase)
                    target.buildPhases.append(phase)
                    return phase
                }()
            fwPhase.files?.append(buildFile)
        }

        // Also add a local package (simulating the macro package)
        let localRef = XCLocalSwiftPackageReference(relativePath: "../MacroKit")
        xcodeproj.pbxproj.add(object: localRef)
        project.localPackages.append(localRef)

        try xcodeproj.write(path: projectPath)

        // NOW use the tool to add a new package — this is the crash scenario
        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/pointfreeco/swift-dependencies"),
            "requirement": Value.string("from: 1.8.1"),
            "target_name": Value.string("Core"),
            "product_name": Value.string("Dependencies"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added Swift Package"))

        // Verify the new package was added alongside existing ones
        let reloaded = try XcodeProj(path: projectPath)
        let reloadedProject = try #require(try reloaded.pbxproj.rootProject())
        let remoteCount = reloadedProject.remotePackages.count
        #expect(
            remoteCount == 4,
            "Should have 3 existing + 1 new remote package, got \(remoteCount)",
        )

        let reloadedTarget = try #require(reloaded.pbxproj.nativeTargets
            .first { $0.name == "Core" })
        let depCount = reloadedTarget.packageProductDependencies?.count ?? 0
        #expect(depCount == 4, "Should have 3 existing + 1 new product dependency, got \(depCount)")
    }

    /// Regression test for the PBXProjWriter workaround (issue 2fi-f1h): projects with sub-project references
    /// where the PBXFileReference has only `path` (no `name`) would crash in
    /// PBXProjEncoder.sortProjectReferences due to a force-unwrap of `name`.
    @Test
    func `Write project with nameless project reference`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Reload, add a sub-project reference with path but NO name (triggers the bug)
        let xcodeproj = try XcodeProj(path: projectPath)
        let project = try #require(try xcodeproj.pbxproj.rootProject())

        let subProjectRef = PBXFileReference(
            sourceTree: .group,
            path: "Vendor/Sub.xcodeproj",
        )
        // name is intentionally nil — this is the crash scenario
        #expect(subProjectRef.name == nil)
        xcodeproj.pbxproj.add(object: subProjectRef)

        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        xcodeproj.pbxproj.add(object: productsGroup)

        project.projects = [[
            "ProjectRef": subProjectRef,
            "ProductGroup": productsGroup,
        ]]

        // Without the PBXProjWriter workaround this crashes with SIGTRAP in release mode
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        // Verify name was backfilled from path
        #expect(subProjectRef.name == "Vendor/Sub.xcodeproj")
    }

    @Test
    func `Add package with invalid target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-collections.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("NonExistentTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}
