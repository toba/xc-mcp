import Foundation
import MCP
import Testing
import XCMCPCore
@testable import XCMCPTools

struct DumpPIFToolTests {
    @Test
    func `Tool metadata`() {
        let tool = DumpPIFTool(pathUtility: PathUtility(basePath: "/tmp")).tool()
        #expect(tool.name == "dump_pif")
    }

    @Test
    func `Requires project_path`() {
        let tool = DumpPIFTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
    }

    @Test
    func `Summary surfaces duplicate target guids`() throws {
        let fixture = try TestPIFCacheFixture.makeWithDuplicateCoreTarget()
        defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

        let tool = DumpPIFTool(pathUtility: PathUtility(basePath: "/", sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string("/tmp/Thesis.xcodeproj"),
            "derived_data_path": .string(fixture.derivedDataRoot),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("expected text")
            return
        }
        #expect(text.contains("Duplicate target guids"))
        #expect(text.contains(fixture.coreGuid))
        #expect(text.contains("Core"))
    }

    @Test
    func `Scope=target returns matching target JSON`() throws {
        let fixture = try TestPIFCacheFixture.makeWithDuplicateCoreTarget()
        defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

        let tool = DumpPIFTool(pathUtility: PathUtility(basePath: "/", sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string("/tmp/Thesis.xcodeproj"),
            "derived_data_path": .string(fixture.derivedDataRoot),
            "scope": .string("target"),
            "name": .string("Core"),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("expected text")
            return
        }
        // Two duplicates -> both rendered with their respective JSONs.
        #expect(text.contains(fixture.coreGuid))
        #expect(text.contains("```json"))
    }

    @Test
    func `Unknown target name returns helpful message`() throws {
        let fixture = try TestPIFCacheFixture.makeWithDuplicateCoreTarget()
        defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

        let tool = DumpPIFTool(pathUtility: PathUtility(basePath: "/", sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string("/tmp/Thesis.xcodeproj"),
            "derived_data_path": .string(fixture.derivedDataRoot),
            "scope": .string("target"),
            "name": .string("Ghost"),
        ])
        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("expected text")
            return
        }
        #expect(text.contains("No PIF target named 'Ghost'"))
    }
}
