import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct StartMacLogCapToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and properties`() {
        let tool = StartMacLogCapTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "start_mac_log_cap")
        #expect(schema.description?.contains("macOS") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
        let tool = StartMacLogCapTool(sessionManager: sessionManager)
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
        #expect(properties["output_file"] != nil)
    }
}

struct StopMacLogCapToolTests {
    let sessionManager = SessionManager()

    @Test
    func `tool schema`() {
        let tool = StopMacLogCapTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "stop_mac_log_cap")
        #expect(schema.description?.contains("macOS") == true)
    }

    @Test
    func `tool parameters`() {
        let tool = StopMacLogCapTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["pid"] != nil)
        #expect(properties["output_file"] != nil)
        #expect(properties["tail_lines"] != nil)
    }
}
