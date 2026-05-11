import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct PredicateFilterValidatorTests {
    @Test
    func `accepts well-formed bundle identifier`() throws {
        try PredicateFilterValidator.validate("com.apple.CloudKit", field: "bundle_id")
        try PredicateFilterValidator.validate("MyApp-Beta_2", field: "process_name")
        try PredicateFilterValidator.validate("com.example.app.sub.module", field: "subsystem")
    }

    @Test
    func `rejects empty value`() {
        #expect(throws: PredicateFilterError.self) {
            try PredicateFilterValidator.validate("", field: "bundle_id")
        }
    }

    @Test
    func `rejects double-quote injection`() {
        #expect(throws: PredicateFilterError.self) {
            try PredicateFilterValidator.validate(
                "com.evil\" OR subsystem == \"com.apple",
                field: "bundle_id",
            )
        }
    }

    @Test
    func `rejects single-quote injection`() {
        #expect(throws: PredicateFilterError.self) {
            try PredicateFilterValidator.validate(
                "com.evil' OR subsystem CONTAINS 'com.apple",
                field: "bundle_id",
            )
        }
    }

    @Test
    func `rejects whitespace`() {
        #expect(throws: PredicateFilterError.self) {
            try PredicateFilterValidator.validate("com.example app", field: "bundle_id")
        }
    }

    @Test
    func `rejects predicate operators`() {
        for value in ["a==b", "a OR b", "a&&b", "a||b", "a;b", "a\\b"] {
            #expect(throws: PredicateFilterError.self) {
                try PredicateFilterValidator.validate(value, field: "subsystem")
            }
        }
    }

    @Test
    func `error converts to invalidParams MCPError`() {
        let error = PredicateFilterError.invalidValue(field: "bundle_id", value: "bad\"")
        let mcpError = error.toMCPError()
        if case let .invalidParams(message) = mcpError {
            #expect(message?.contains("bundle_id") == true)
            #expect(message?.contains("bad\"") == true)
        } else {
            Issue.record("Expected .invalidParams, got \(mcpError)")
        }
    }

    @Test
    func `StartSimLogCapTool rejects injected bundle_id`() async throws {
        let tool = StartSimLogCapTool(sessionManager: SessionManager())
        await #expect(throws: MCPError.self) {
            _ = try await tool.execute(arguments: [
                "simulator": .string("ABCDEFGH"),
                "bundle_id": .string("com.evil\" OR processImagePath CONTAINS \"Apple"),
            ])
        }
    }

    @Test
    func `StartMacLogCapTool rejects injected subsystem`() async throws {
        let tool = StartMacLogCapTool(sessionManager: SessionManager())
        await #expect(throws: MCPError.self) {
            _ = try await tool.execute(arguments: [
                "subsystem": .string("com.apple\" OR process == \"loginwindow"),
            ])
        }
    }

    @Test
    func `ShowMacLogTool rejects injected process_name`() async throws {
        let tool = ShowMacLogTool(sessionManager: SessionManager())
        await #expect(throws: MCPError.self) {
            _ = try await tool.execute(arguments: [
                "process_name": .string("Finder\" OR process == \"loginwindow"),
            ])
        }
    }
}
