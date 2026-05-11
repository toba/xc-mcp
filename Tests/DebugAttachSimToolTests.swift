import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct DebugAttachSimToolTests {
    @Test
    func `Tool schema declares bundle_id, simulator, and pid as optional`() {
        let tool = DebugAttachSimTool(sessionManager: SessionManager())
        let schema = tool.tool()

        #expect(schema.name == "debug_attach_sim")

        guard case let .object(input) = schema.inputSchema,
              case let .object(properties) = input["properties"],
              case let .array(required) = input["required"]
        else {
            Issue.record("Expected object schema with properties + required array")
            return
        }

        #expect(properties["bundle_id"] != nil)
        #expect(properties["simulator"] != nil)
        #expect(properties["pid"] != nil)
        // Neither bundle_id nor pid is required at the schema level; the tool resolves
        // precedence at execute() time (explicit pid wins, then bundle_id, then error).
        #expect(required.isEmpty)
    }

    @Test
    func `execute with neither pid nor bundle_id throws invalidParams`() async {
        let tool = DebugAttachSimTool(sessionManager: SessionManager())
        do {
            _ = try await tool.execute(arguments: [:])
            Issue.record("Expected invalidParams error")
        } catch let error as MCPError {
            if case let .invalidParams(message) = error {
                #expect(message?.contains("bundle_id") == true || message?.contains("pid") == true)
            } else {
                Issue.record("Expected .invalidParams, got \(error)")
            }
        } catch {
            Issue.record("Expected MCPError, got \(type(of: error))")
        }
    }

    // Regression: SessionManager in xc-mcp does not store a `bundle_id` default
    // (only `simulatorUDID`), so the upstream XcodeBuildMCP #411 bug — where an
    // inherited `bundle_id` from session defaults tripped mutual-exclusion validation
    // when the caller passed an explicit `pid` — cannot occur here. This test locks
    // in that contract by confirming SessionManager exposes no `bundleId` surface.
    @Test
    func `SessionManager does not store bundle_id as a session default`() async {
        let manager = SessionManager()
        // If a `bundleId` property is ever added to SessionManager that gets applied
        // as a default in tool argument merging, this Mirror-based check will need
        // to be revisited together with DebugAttachSimTool's precedence logic.
        let mirror = Mirror(reflecting: manager)
        let hasBundleIdField = mirror.children.contains {
            $0.label?.lowercased().contains("bundleid") == true
        }
        #expect(!hasBundleIdField, "SessionManager must not store a bundle_id default — see issue a3v-j0l")
        _ = await manager.simulatorUDID
    }
}
