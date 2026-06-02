import Foundation
import MCP
import Testing
import XCMCPCore
@testable import XCMCPTools

struct WhyTargetIdToolTests {
    @Test
    func `Tool metadata`() {
        let tool = WhyTargetIdTool(pathUtility: PathUtility(basePath: "/tmp")).tool()
        #expect(tool.name == "why_target_id")
    }

    @Test
    func `Requires both arguments`() {
        let tool = WhyTargetIdTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) { try tool.execute(arguments: [:]) }
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/tmp/x.xcodeproj")])
        }
    }

    @Test
    func `Rejects target_id without a 64-char hex hash`() throws {
        let fixture = try TestPIFCacheFixture.makeWithDuplicateCoreTarget()
        defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

        let tool = WhyTargetIdTool(pathUtility: PathUtility(basePath: "/", sandboxEnabled: false))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/tmp/Thesis.xcodeproj"),
                "target_id": .string("no hash here"),
                "derived_data_path": .string(fixture.derivedDataRoot),
            ])
        }
    }

    @Test
    func `Surfaces duplicate target guid and its consumer`() throws {
        let fixture = try TestPIFCacheFixture.makeWithDuplicateCoreTarget()
        defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

        let tool = WhyTargetIdTool(pathUtility: PathUtility(basePath: "/", sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string("/tmp/Thesis.xcodeproj"),
            "target_id":
                .string("target-Core-\(fixture.coreGuid)-SDKROOT:iphonesimulator"),
            "derived_data_path": .string(fixture.derivedDataRoot),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("expected text")
            return
        }
        #expect(text.contains("2 targets share this guid"))
        #expect(text.contains("Match #1: Core"))
        #expect(text.contains("Match #2: Core"))
        // Project owners surfaced.
        #expect(text.contains("Thesis"))
        #expect(text.contains("ThesisOther"))
        // Consumer ThesisApp depends on Core.
        #expect(text.contains("ThesisApp"))
    }

    @Test
    func `Reports no match when the guid is unknown`() throws {
        let fixture = try TestPIFCacheFixture.makeWithDuplicateCoreTarget()
        defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

        let unknown = String(repeating: "f", count: 64)
        let tool = WhyTargetIdTool(pathUtility: PathUtility(basePath: "/", sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string("/tmp/Thesis.xcodeproj"),
            "target_id": .string(unknown),
            "derived_data_path": .string(fixture.derivedDataRoot),
        ])
        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("expected text")
            return
        }
        #expect(text.contains("No PIF target carries this guid"))
    }
}
