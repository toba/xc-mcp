import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct ShowMacLogToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = ShowMacLogTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "show_mac_log")
        #expect(schema.description?.contains("historical") == true)
        #expect(schema.description?.contains("log show") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
        let tool = ShowMacLogTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["bundle_id"] != nil)
        #expect(properties["process_name"] != nil)
        #expect(properties["subsystem"] != nil)
        #expect(properties["predicate"] != nil)
        #expect(properties["level"] != nil)
        #expect(properties["last"] != nil)
        #expect(properties["start"] != nil)
        #expect(properties["end"] != nil)
        #expect(properties["tail_lines"] != nil)
    }

    @Test
    func `Time parameters have string type`() {
        let tool = ShowMacLogTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"],
              case let .object(lastProp) = properties["last"],
              case let .object(startProp) = properties["start"],
              case let .object(endProp) = properties["end"]
        else {
            Issue.record("Expected object properties for time parameters")
            return
        }

        #expect(lastProp["type"] == .string("string"))
        #expect(startProp["type"] == .string("string"))
        #expect(endProp["type"] == .string("string"))
    }

    @Test
    func `Tail lines parameter has integer type`() {
        let tool = ShowMacLogTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"],
              case let .object(tailLinesProp) = properties["tail_lines"]
        else {
            Issue.record("Expected object property for tail_lines")
            return
        }

        #expect(tailLinesProp["type"] == .string("integer"))
    }
}
