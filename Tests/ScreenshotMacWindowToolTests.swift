import MCP
import Testing
@testable import XCMCPTools

@Suite("ScreenshotMacWindowTool Tests")
struct ScreenshotMacWindowToolTests {
    @Test("Tool schema has correct name and description")
    func toolSchema() {
        let tool = ScreenshotMacWindowTool()
        let schema = tool.tool()

        #expect(schema.name == "screenshot_mac_window")
        #expect(schema.description?.contains("screenshot") == true)
        #expect(schema.description?.contains("ScreenCaptureKit") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func toolParameters() {
        let tool = ScreenshotMacWindowTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["app_name"] != nil)
        #expect(properties["bundle_id"] != nil)
        #expect(properties["window_title"] != nil)
        #expect(properties["save_path"] != nil)
    }

    @Test("Execute with no arguments throws invalidParams")
    func noArguments() async throws {
        let tool = ScreenshotMacWindowTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }
}
