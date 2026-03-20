import MCP
import Testing
import Foundation
@testable import XCMCPTools

struct ExportIconToolTests {
    let tool = ExportIconTool()

    // MARK: - Tool metadata

    @Test
    func `Tool name and description are correct`() {
        let definition = tool.tool()
        #expect(definition.name == "export_icon")
        #expect(definition.description?.contains("ictool") == true)
    }

    // MARK: - Missing required parameters

    @Test
    func `Missing icon_path throws invalidParams`() async {
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "output_path": .string("/tmp/out.png"),
            ])
        }
    }

    @Test
    func `Missing output_path throws invalidParams`() async {
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "icon_path": .string("/tmp/test.icon"),
            ])
        }
    }

    // MARK: - Invalid input

    @Test
    func `Nonexistent icon file throws invalidParams`() async {
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "icon_path": .string("/tmp/nonexistent-\(UUID()).icon"),
                "output_path": .string("/tmp/out.png"),
            ])
        }
    }

    // MARK: - Integration test (requires Icon Composer installed)

    @Test(.enabled(if: FileManager.default
            .fileExists(atPath: "/Applications/Icon Composer.app/Contents/Executables/ictool")))
    func `Export thesis icon to PNG`() async throws {
        let iconPath = "/Users/jason/Developer/toba/thesis/AppIcon.icon"
        guard FileManager.default.fileExists(atPath: iconPath) else {
            Issue.record("Thesis AppIcon.icon not found at \(iconPath)")
            return
        }

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-icon-test-\(UUID()).png").path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        let result = try await tool.execute(arguments: [
            "icon_path": .string(iconPath),
            "output_path": .string(outputPath),
            "platform": .string("macOS"),
            "rendition": .string("Default"),
            "width": .int(256),
            "height": .int(256),
            "scale": .int(1),
        ])

        let text = try #require(result.content.first.flatMap {
            if case let .text(t) = $0 { return t }
            return nil
        })
        #expect(text.contains("Exported icon to"))
        #expect(text.contains("256x256"))
        #expect(FileManager.default.fileExists(atPath: outputPath))

        // Verify it's a valid PNG (starts with PNG signature)
        let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        #expect(data.count > 8)
        #expect(data[0] == 0x89)
        #expect(data[1] == 0x50) // P
        #expect(data[2] == 0x4E) // N
        #expect(data[3] == 0x47) // G
    }

    @Test(.enabled(if: FileManager.default
            .fileExists(atPath: "/Applications/Icon Composer.app/Contents/Executables/ictool")))
    func `Export at 2x scale produces larger file`() async throws {
        let iconPath = "/Users/jason/Developer/toba/thesis/AppIcon.icon"
        guard FileManager.default.fileExists(atPath: iconPath) else {
            Issue.record("Thesis AppIcon.icon not found at \(iconPath)")
            return
        }

        let output1x = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-icon-1x-\(UUID()).png").path
        let output2x = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-icon-2x-\(UUID()).png").path
        defer {
            try? FileManager.default.removeItem(atPath: output1x)
            try? FileManager.default.removeItem(atPath: output2x)
        }

        _ = try await tool.execute(arguments: [
            "icon_path": .string(iconPath),
            "output_path": .string(output1x),
            "width": .int(128),
            "height": .int(128),
            "scale": .int(1),
        ])
        _ = try await tool.execute(arguments: [
            "icon_path": .string(iconPath),
            "output_path": .string(output2x),
            "width": .int(128),
            "height": .int(128),
            "scale": .int(2),
        ])

        let size1x = try #require(FileManager.default
            .attributesOfItem(atPath: output1x)[.size] as? UInt64)
        let size2x = try #require(FileManager.default
            .attributesOfItem(atPath: output2x)[.size] as? UInt64)
        #expect(size2x > size1x, "2x scale should produce a larger PNG than 1x")
    }
}
