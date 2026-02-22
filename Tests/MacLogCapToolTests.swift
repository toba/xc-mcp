import MCP
import Testing

@testable import XCMCPCore
@testable import XCMCPTools

@Suite("StartMacLogCapTool Tests")
struct StartMacLogCapToolTests {
  let sessionManager = SessionManager()

  @Test("Tool schema has correct name and properties")
  func toolSchema() {
    let tool = StartMacLogCapTool(sessionManager: sessionManager)
    let schema = tool.tool()

    #expect(schema.name == "start_mac_log_cap")
    #expect(schema.description?.contains("macOS") == true)
  }

  @Test("Tool schema includes all expected parameters")
  func toolParameters() {
    let tool = StartMacLogCapTool(sessionManager: sessionManager)
    let schema = tool.tool()

    guard case .object(let inputSchema) = schema.inputSchema,
      case .object(let properties) = inputSchema["properties"]
    else {
      Issue.record("Expected object input schema with properties")
      return
    }

    #expect(properties["bundle_id"] != nil)
    #expect(properties["process_name"] != nil)
    #expect(properties["subsystem"] != nil)
    #expect(properties["predicate"] != nil)
    #expect(properties["output_file"] != nil)
  }
}

@Suite("StopMacLogCapTool Tests")
struct StopMacLogCapToolTests {
  let sessionManager = SessionManager()

  @Test("Tool schema has correct name and properties")
  func testToolSchema() {
    let tool = StopMacLogCapTool(sessionManager: sessionManager)
    let schema = tool.tool()

    #expect(schema.name == "stop_mac_log_cap")
    #expect(schema.description?.contains("macOS") == true)
  }

  @Test("Tool schema includes all expected parameters")
  func testToolParameters() {
    let tool = StopMacLogCapTool(sessionManager: sessionManager)
    let schema = tool.tool()

    guard case .object(let inputSchema) = schema.inputSchema,
      case .object(let properties) = inputSchema["properties"]
    else {
      Issue.record("Expected object input schema with properties")
      return
    }

    #expect(properties["pid"] != nil)
    #expect(properties["output_file"] != nil)
    #expect(properties["tail_lines"] != nil)
  }
}
