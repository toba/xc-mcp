import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct CreateIconToolTests {
    @Test
    func `Tool creation`() {
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "create_icon")
        #expect(definition.description?.contains("Icon Composer") == true)
    }

    @Test
    func `Missing png_path throws`() {
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "output_path": .string("/tmp/AppIcon.icon"),
            ])
        }
    }

    @Test
    func `Missing output_path throws`() {
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "png_path": .string("/tmp/logo.png"),
            ])
        }
    }

    @Test
    func `Output path without icon extension throws`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngPath = tempDir.appendingPathComponent("logo.png")
        try Data([0x89, 0x50]).write(to: pngPath)

        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "png_path": .string(pngPath.path),
                "output_path": .string(tempDir.appendingPathComponent("AppIcon").path),
            ])
        }
    }

    @Test
    func `Nonexistent PNG throws`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "png_path": .string(tempDir.appendingPathComponent("missing.png").path),
                "output_path": .string(tempDir.appendingPathComponent("AppIcon.icon").path),
            ])
        }
    }

    @Test
    func `Creates icon bundle with correct structure`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a dummy PNG
        let pngPath = tempDir.appendingPathComponent("logo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let outputPath = tempDir.appendingPathComponent("AppIcon.icon")
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "png_path": .string(pngPath.path),
            "output_path": .string(outputPath.path),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Created AppIcon.icon"))

        // Verify bundle structure
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: outputPath.path))
        #expect(fm.fileExists(atPath: outputPath.appendingPathComponent("icon.json").path))
        #expect(fm.fileExists(atPath: outputPath.appendingPathComponent("Assets/logo.png").path))
    }

    @Test
    func `Icon json is valid and contains expected fields`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngPath = tempDir.appendingPathComponent("glyph.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let outputPath = tempDir.appendingPathComponent("AppIcon.icon")
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "png_path": .string(pngPath.path),
            "output_path": .string(outputPath.path),
            "layer_name": .string("MyGlyph"),
        ])

        // Parse back the icon.json
        let jsonURL = outputPath.appendingPathComponent("icon.json")
        let data = try Data(contentsOf: jsonURL)
        let manifest = try JSONDecoder().decode(IconManifest.self, from: data)

        #expect(manifest.groups.count == 1)
        #expect(manifest.groups[0].layers.count == 1)
        #expect(manifest.groups[0].layers[0].imageName == "glyph.png")
        #expect(manifest.groups[0].layers[0].name == "MyGlyph")
        #expect(manifest.groups[0].shadow?.kind == "neutral")
        #expect(manifest.groups[0].translucency?.enabled == true)
    }

    @Test
    func `Fill color from hex is converted to sRGB`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngPath = tempDir.appendingPathComponent("icon.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let outputPath = tempDir.appendingPathComponent("AppIcon.icon")
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "png_path": .string(pngPath.path),
            "output_path": .string(outputPath.path),
            "fill_color": .string("#FF0000"),
        ])

        let data = try Data(contentsOf: outputPath.appendingPathComponent("icon.json"))
        let manifest = try JSONDecoder().decode(IconManifest.self, from: data)

        guard case let .automaticGradient(color) = manifest.fill else {
            Issue.record("Expected automatic-gradient fill, got \(String(describing: manifest.fill))")
            return
        }
        #expect(color.contains("1.00000,0.00000,0.00000"))
    }

    @Test
    func `Dark fill color creates specialization`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngPath = tempDir.appendingPathComponent("icon.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let outputPath = tempDir.appendingPathComponent("AppIcon.icon")
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "png_path": .string(pngPath.path),
            "output_path": .string(outputPath.path),
            "fill_color": .string("#FFFFFF"),
            "dark_fill_color": .string("#000000"),
        ])

        let data = try Data(contentsOf: outputPath.appendingPathComponent("icon.json"))
        let manifest = try JSONDecoder().decode(IconManifest.self, from: data)

        #expect(manifest.fill != nil)
        #expect(manifest.fillSpecializations?.count == 1)
        #expect(manifest.fillSpecializations?[0].appearance == "dark")
    }

    @Test
    func `Glyph scale creates position`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngPath = tempDir.appendingPathComponent("icon.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let outputPath = tempDir.appendingPathComponent("AppIcon.icon")
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "png_path": .string(pngPath.path),
            "output_path": .string(outputPath.path),
            "glyph_scale": .double(0.75),
        ])

        let data = try Data(contentsOf: outputPath.appendingPathComponent("icon.json"))
        let manifest = try JSONDecoder().decode(IconManifest.self, from: data)

        #expect(manifest.groups[0].layers[0].position?.scale == 0.75)
    }

    @Test
    func `Creates icon and adds to Xcode project`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        let pngPath = tempDir.appendingPathComponent("logo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "png_path": .string(pngPath.path),
            "output_path": .string(tempDir.appendingPathComponent("AppIcon.icon").path),
            "project_path": .string(projectPath.string),
            "target_name": .string("TestApp"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Created AppIcon.icon"))
        #expect(message.contains("Successfully added file"))

        // Verify the file reference has correct type
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileRef = xcodeproj.pbxproj.fileReferences.first { $0.name == "AppIcon.icon" }
        #expect(fileRef != nil)
        #expect(
            fileRef?.lastKnownFileType == "folder.iconcomposer.icon",
            "lastKnownFileType should be folder.iconcomposer.icon, got: \(fileRef?.lastKnownFileType ?? "nil")",
        )

        // Verify it's in the resources build phase
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }!
        let resourcesBuildPhase =
            target.buildPhases.first { $0 is PBXResourcesBuildPhase } as? PBXResourcesBuildPhase
        let resourceFiles = resourcesBuildPhase?.files?.compactMap { $0.file?.name } ?? []
        #expect(resourceFiles.contains("AppIcon.icon"))
    }

    @Test
    func `Shadow none omits shadow from manifest`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngPath = tempDir.appendingPathComponent("icon.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let outputPath = tempDir.appendingPathComponent("AppIcon.icon")
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "png_path": .string(pngPath.path),
            "output_path": .string(outputPath.path),
            "shadow_kind": .string("none"),
        ])

        let data = try Data(contentsOf: outputPath.appendingPathComponent("icon.json"))
        let manifest = try JSONDecoder().decode(IconManifest.self, from: data)

        #expect(manifest.groups[0].shadow == nil)
    }
}
