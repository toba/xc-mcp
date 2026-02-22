import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("InfoPlistUtility Tests")
struct InfoPlistUtilityTests {
    @Test("resolveInfoPlistPath returns nil when target not found")
    func resolveInfoPlistPathTargetNotFound() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let result = InfoPlistUtility.resolveInfoPlistPath(
            xcodeproj: xcodeproj, projectDir: tempDir.path, targetName: "NonExistent"
        )

        #expect(result == nil)
    }

    @Test("resolveInfoPlistPath returns nil when no INFOPLIST_FILE set")
    func resolveInfoPlistPathNoSetting() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let result = InfoPlistUtility.resolveInfoPlistPath(
            xcodeproj: xcodeproj, projectDir: tempDir.path, targetName: "App"
        )

        #expect(result == nil)
    }

    @Test("resolveInfoPlistPath returns path when INFOPLIST_FILE is set and file exists")
    func resolveInfoPlistPathSuccess() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Create an Info.plist file
        let plistPath = tempDir.appendingPathComponent("App/Info.plist")
        try FileManager.default.createDirectory(
            at: plistPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let emptyPlist: [String: Any] = [:]
        let data = try PropertyListSerialization.data(
            fromPropertyList: emptyPlist, format: .xml, options: 0
        )
        try data.write(to: plistPath)

        // Set INFOPLIST_FILE in build settings
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let configs = target.buildConfigurationList?.buildConfigurations ?? []
        for config in configs {
            config.buildSettings["INFOPLIST_FILE"] = "App/Info.plist"
        }
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let reloaded = try XcodeProj(path: projectPath)
        let result = InfoPlistUtility.resolveInfoPlistPath(
            xcodeproj: reloaded, projectDir: tempDir.path, targetName: "App"
        )

        #expect(result != nil)
        #expect(result?.hasSuffix("App/Info.plist") == true)
    }

    @Test("readInfoPlist reads valid plist")
    func readInfoPlistSuccess() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistPath = tempDir.appendingPathComponent("Info.plist").path
        let testPlist: [String: Any] = ["CFBundleName": "TestApp", "CFBundleVersion": "1.0"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: testPlist, format: .xml, options: 0
        )
        try data.write(to: URL(fileURLWithPath: plistPath))

        let result = try InfoPlistUtility.readInfoPlist(path: plistPath)
        #expect(result["CFBundleName"] as? String == "TestApp")
        #expect(result["CFBundleVersion"] as? String == "1.0")
    }

    @Test("readInfoPlist throws for missing file")
    func readInfoPlistMissingFile() {
        #expect(throws: MCPError.self) {
            try InfoPlistUtility.readInfoPlist(path: "/nonexistent/Info.plist")
        }
    }

    @Test("writeInfoPlist writes and reads back correctly")
    func writeInfoPlistRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistPath = tempDir.appendingPathComponent("Info.plist").path
        let testPlist: [String: Any] = [
            "CFBundleName": "TestApp",
            "CFBundleDocumentTypes": [
                ["CFBundleTypeName": "Test Document", "CFBundleTypeRole": "Editor"]
            ] as [[String: Any]],
        ]

        try InfoPlistUtility.writeInfoPlist(testPlist, toPath: plistPath)
        let readBack = try InfoPlistUtility.readInfoPlist(path: plistPath)

        #expect(readBack["CFBundleName"] as? String == "TestApp")
        let docTypes = readBack["CFBundleDocumentTypes"] as? [[String: Any]]
        #expect(docTypes?.count == 1)
        #expect(docTypes?.first?["CFBundleTypeName"] as? String == "Test Document")
    }

    @Test("materializeInfoPlist creates file and sets build setting")
    func materializeInfoPlist() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let plistAbsPath = try InfoPlistUtility.materializeInfoPlist(
            xcodeproj: xcodeproj, projectDir: tempDir.path, targetName: "App",
            projectPath: projectPath
        )

        // Verify the file was created
        #expect(FileManager.default.fileExists(atPath: plistAbsPath))
        #expect(plistAbsPath.hasSuffix("App/Info.plist"))

        // Verify the build setting was updated
        let reloaded = try XcodeProj(path: projectPath)
        let target = try #require(reloaded.pbxproj.nativeTargets.first { $0.name == "App" })
        let configs = target.buildConfigurationList?.buildConfigurations ?? []
        for config in configs {
            #expect(config.buildSettings["INFOPLIST_FILE"]?.stringValue == "App/Info.plist")
        }
    }
}
