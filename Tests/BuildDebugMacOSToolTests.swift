import MCP
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

struct BuildDebugMacOSToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and documents skip_build`() {
        let tool = BuildDebugMacOSTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "build_debug_macos")
        #expect(schema.description?.contains("skip_build") == true)
    }

    @Test
    func `Tool schema exposes skip_build boolean parameter`() {
        let tool = BuildDebugMacOSTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"],
              case let .object(skipBuild) = properties["skip_build"]
        else {
            Issue.record("Expected skip_build property in input schema")
            return
        }

        #expect(skipBuild["type"] == .string("boolean"))
        // Sanity-check the launch-time knobs it pairs with are still present.
        #expect(properties["env"] != nil)
        #expect(properties["args"] != nil)
    }
}
