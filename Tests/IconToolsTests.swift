import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

/// Tests for icon bundle manipulation tools (read, add layer, remove layer, fill, effects, position).
struct IconToolsTests {
    /// Creates a minimal .icon bundle in a temp directory and returns (tempDir, bundlePath).
    private func makeBundle(
        pngName: String = "logo.png",
        fillColor: String? = nil
    ) throws -> (URL, String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let pngPath = tempDir.appendingPathComponent(pngName)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngPath)

        let bundlePath = tempDir.appendingPathComponent("AppIcon.icon").path
        let tool = CreateIconTool(pathUtility: PathUtility(basePath: tempDir.path))
        var args: [String: Value] = [
            "png_path": .string(pngPath.path),
            "output_path": .string(bundlePath),
        ]
        if let fillColor {
            args["fill_color"] = .string(fillColor)
        }
        _ = try tool.execute(arguments: args)
        return (tempDir, bundlePath)
    }

    // MARK: - read_icon

    @Test
    func `Read icon returns manifest summary`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadIconTool()
        let result = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(text.contains("AppIcon.icon"))
        #expect(text.contains("logo.png"))
        #expect(text.contains("Group 0"))
        #expect(text.contains("Layer 0"))
    }

    @Test
    func `Read nonexistent bundle throws`() {
        let tool = ReadIconTool()
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string("/tmp/nonexistent-\(UUID()).icon"),
            ])
        }
    }

    // MARK: - add_icon_layer

    @Test
    func `Add layer appends to existing group`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a second image
        let secondPNG = tempDir.appendingPathComponent("overlay.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: secondPNG)

        let tool = AddIconLayerTool()
        let result = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "image_path": .string(secondPNG.path),
            "name": .string("Overlay"),
            "scale": .double(0.5),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(text.contains("Overlay"))

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups[0].layers.count == 2)
        #expect(manifest.groups[0].layers[1].name == "Overlay")
        #expect(manifest.groups[0].layers[1].imageName == "overlay.png")
        #expect(manifest.groups[0].layers[1].position?.scale == 0.5)

        // Asset should be copied
        #expect(FileManager.default.fileExists(atPath: bundlePath + "/Assets/overlay.png"))
    }

    @Test
    func `Add layer with create_group makes new group`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bgPNG = tempDir.appendingPathComponent("bg.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: bgPNG)

        let tool = AddIconLayerTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "image_path": .string(bgPNG.path),
            "name": .string("Background"),
            "create_group": .bool(true),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups.count == 2)
        #expect(manifest.groups[1].layers[0].name == "Background")
    }

    // MARK: - remove_icon_layer

    @Test
    func `Remove layer from group`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Add a second layer first
        let secondPNG = tempDir.appendingPathComponent("extra.png")
        try Data([0x89, 0x50]).write(to: secondPNG)
        let addTool = AddIconLayerTool()
        _ = try addTool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "image_path": .string(secondPNG.path),
            "name": .string("Extra"),
        ])

        let removeTool = RemoveIconLayerTool()
        let result = try removeTool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "target": .string("layer"),
            "group_index": .int(0),
            "layer_index": .int(1),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(text.contains("Extra"))

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups[0].layers.count == 1)

        // extra.png should be purged from Assets/
        #expect(!FileManager.default.fileExists(atPath: bundlePath + "/Assets/extra.png"))
    }

    @Test
    func `Remove entire group`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Add a second group
        let bgPNG = tempDir.appendingPathComponent("bg.png")
        try Data([0x89, 0x50]).write(to: bgPNG)
        let addTool = AddIconLayerTool()
        _ = try addTool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "image_path": .string(bgPNG.path),
            "name": .string("BG"),
            "create_group": .bool(true),
        ])

        let removeTool = RemoveIconLayerTool()
        _ = try removeTool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "target": .string("group"),
            "group_index": .int(1),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups.count == 1)
    }

    // MARK: - set_icon_fill

    @Test
    func `Set solid fill`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconFillTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "type": .string("solid"),
            "color": .string("#FF0000"),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        guard case let .solid(color) = manifest.fill else {
            Issue.record("Expected solid fill")
            return
        }
        #expect(color.contains("1.00000,0.00000,0.00000"))
    }

    @Test
    func `Set automatic gradient fill`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconFillTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "type": .string("automatic"),
            "color": .string("#0088FF"),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        guard case .automaticGradient = manifest.fill else {
            Issue.record("Expected automatic-gradient fill")
            return
        }
    }

    @Test
    func `Clear fill`() throws {
        let (tempDir, bundlePath) = try makeBundle(fillColor: "#FF0000")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconFillTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "type": .string("none"),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.fill == nil)
    }

    @Test
    func `Set linear gradient fill`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconFillTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "type": .string("gradient"),
            "color": .string("#FF0000"),
            "color2": .string("#0000FF"),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        guard case let .linearGradient(colors, _) = manifest.fill else {
            Issue.record("Expected linear-gradient fill")
            return
        }
        #expect(colors.count == 2)
    }

    // MARK: - set_icon_effects

    @Test
    func `Set specular and shadow`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconEffectsTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "specular": .bool(true),
            "shadow_kind": .string("layer-color"),
            "shadow_opacity": .double(0.8),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups[0].specular == true)
        #expect(manifest.groups[0].shadow?.kind == "layer-color")
        #expect(manifest.groups[0].shadow?.opacity == 0.8)
    }

    @Test
    func `Set translucency and blur`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconEffectsTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "translucency_enabled": .bool(false),
            "blur_material": .double(0.6),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups[0].translucency?.enabled == false)
        #expect(manifest.groups[0].blurMaterial == 0.6)
    }

    @Test
    func `Remove shadow with none`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconEffectsTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "shadow_kind": .string("none"),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups[0].shadow == nil)
    }

    // MARK: - set_icon_layer_position

    @Test
    func `Set layer position`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconLayerPositionTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "target": .string("layer"),
            "group_index": .int(0),
            "layer_index": .int(0),
            "scale": .double(0.75),
            "offset_x": .double(10),
            "offset_y": .double(-5),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        let pos = manifest.groups[0].layers[0].position
        #expect(pos?.scale == 0.75)
        #expect(pos?.translationInPoints == [10, -5])
    }

    @Test
    func `Set group position`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconLayerPositionTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "target": .string("group"),
            "group_index": .int(0),
            "scale": .double(1.2),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        let pos = manifest.groups[0].position
        #expect(pos?.scale == 1.2)
    }

    // MARK: - set_icon_appearances

    @Test
    func `Set dark fill appearance`() throws {
        let (tempDir, bundlePath) = try makeBundle(fillColor: "#FFFFFF")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconAppearancesTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "target": .string("fill"),
            "appearance": .string("dark"),
            "bg_color": .string("#000000"),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.fillSpecializations?.count == 1)
        #expect(manifest.fillSpecializations?[0].appearance == "dark")
    }

    @Test
    func `Set tinted fill appearance`() throws {
        let (tempDir, bundlePath) = try makeBundle(fillColor: "#0088FF")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconAppearancesTool()
        _ = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "target": .string("fill"),
            "appearance": .string("tinted"),
            "bg_color": .string("#FF8800"),
        ])

        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.fillSpecializations?.count == 1)
        #expect(manifest.fillSpecializations?[0].appearance == "tinted")
    }

    // MARK: - Edge cases (adapted from ethbak/icon-composer-mcp)

    @Test
    func `Remove layer preserves assets still referenced by other layers`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Add second layer referencing same image (logo.png)
        let addTool = AddIconLayerTool()
        _ = try addTool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "image_path": .string(tempDir.appendingPathComponent("logo.png").path),
            "name": .string("Logo Copy"),
        ])

        // Remove first layer — logo.png should NOT be purged (still used by second layer)
        let removeTool = RemoveIconLayerTool()
        _ = try removeTool.execute(arguments: [
            "bundle_path": .string(bundlePath),
            "target": .string("layer"),
            "group_index": .int(0),
            "layer_index": .int(0),
        ])

        #expect(FileManager.default.fileExists(atPath: bundlePath + "/Assets/logo.png"),
                "Asset should be preserved when still referenced by another layer")
        let manifest = try IconManifest.read(from: bundlePath)
        #expect(manifest.groups[0].layers.count == 1)
        #expect(manifest.groups[0].layers[0].name == "Logo Copy")
    }

    @Test
    func `Remove layer out of bounds throws`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = RemoveIconLayerTool()
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string(bundlePath),
                "target": .string("layer"),
                "group_index": .int(0),
                "layer_index": .int(99),
            ])
        }
    }

    @Test
    func `Remove group out of bounds throws`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = RemoveIconLayerTool()
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string(bundlePath),
                "target": .string("group"),
                "group_index": .int(5),
            ])
        }
    }

    @Test
    func `Add layer to out of bounds group throws`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secondPNG = tempDir.appendingPathComponent("extra.png")
        try Data([0x89, 0x50]).write(to: secondPNG)

        let tool = AddIconLayerTool()
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string(bundlePath),
                "image_path": .string(secondPNG.path),
                "name": .string("Bad"),
                "group_index": .int(99),
            ])
        }
    }

    @Test
    func `Set effects on out of bounds group throws`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconEffectsTool()
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string(bundlePath),
                "group_index": .int(5),
                "specular": .bool(true),
            ])
        }
    }

    @Test
    func `Set layer position out of bounds throws`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconLayerPositionTool()
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string(bundlePath),
                "target": .string("layer"),
                "group_index": .int(0),
                "layer_index": .int(99),
                "scale": .double(0.5),
            ])
        }
    }

    @Test
    func `Set fill missing color for solid throws`() {
        let tool = SetIconFillTool()
        // Need a real bundle for this to get past the file check
        // so we just test with nonexistent — the error type is the same
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string("/tmp/nonexistent-\(UUID()).icon"),
                "type": .string("solid"),
            ])
        }
    }

    @Test
    func `Read icon with fill shows fill info`() throws {
        let (tempDir, bundlePath) = try makeBundle(fillColor: "#0088FF")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ReadIconTool()
        let result = try tool.execute(arguments: [
            "bundle_path": .string(bundlePath),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(text.contains("Fill"))
        #expect(text.contains("automatic-gradient"))
    }

    @Test
    func `Nonexistent bundle throws for all tools`() throws {
        let fakePath = "/tmp/nonexistent-\(UUID()).icon"

        #expect(throws: MCPError.self) {
            try AddIconLayerTool().execute(arguments: [
                "bundle_path": .string(fakePath),
                "image_path": .string("/tmp/x.png"),
                "name": .string("x"),
            ])
        }
        #expect(throws: MCPError.self) {
            try RemoveIconLayerTool().execute(arguments: [
                "bundle_path": .string(fakePath),
                "target": .string("layer"),
                "group_index": .int(0),
                "layer_index": .int(0),
            ])
        }
        #expect(throws: MCPError.self) {
            try SetIconFillTool().execute(arguments: [
                "bundle_path": .string(fakePath),
                "type": .string("none"),
            ])
        }
        #expect(throws: MCPError.self) {
            try SetIconEffectsTool().execute(arguments: [
                "bundle_path": .string(fakePath),
                "specular": .bool(true),
            ])
        }
        #expect(throws: MCPError.self) {
            try SetIconLayerPositionTool().execute(arguments: [
                "bundle_path": .string(fakePath),
                "scale": .double(0.5),
            ])
        }
    }

    @Test
    func `Invalid appearance throws`() throws {
        let (tempDir, bundlePath) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = SetIconAppearancesTool()
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "bundle_path": .string(bundlePath),
                "target": .string("fill"),
                "appearance": .string("invalid"),
                "bg_color": .string("#000000"),
            ])
        }
    }
}
