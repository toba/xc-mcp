import MCP
import Testing
import Foundation
@testable import XCMCPTools

struct SwiftSymbolsToolTests {
    let tool = SwiftSymbolsTool()

    // MARK: - Tool metadata

    @Test
    func `Tool name and description are correct`() {
        let definition = tool.tool()
        #expect(definition.name == "swift_symbols")
        #expect(definition.description?.contains("swift-symbolgraph-extract") == true)
    }

    // MARK: - Missing required parameter

    @Test
    func `Missing module parameter throws invalidParams`() async {
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    // MARK: - Invalid platform

    @Test
    func `Invalid platform throws invalidParams`() async {
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "module": .string("Foundation"),
                "platform": .string("android"),
            ])
        }
    }

    // MARK: - Integration tests (require SDK + time)
    // Foundation symbol graph extraction takes 30-60s, too slow for CI.
    // Testing module is fast (~18s) and validates the same code path.

    @Test
    func `Extract Testing module and find Trait protocol`() async throws {
        let result = try await tool.execute(arguments: [
            "module": .string("Testing"),
            "query": .string("Trait"),
        ])

        let text = try #require(result.content.first.flatMap {
            if case let .text(t) = $0 { return t }
            return nil
        })

        #expect(text.contains("Module: Testing"))
        #expect(text.lowercased().contains("trait"))
    }

    @Test
    func `Query with no matches returns empty result`() async throws {
        let result = try await tool.execute(arguments: [
            "module": .string("Testing"),
            "query": .string("xyzzy_nonexistent_symbol_12345"),
        ])

        let text = try #require(result.content.first.flatMap {
            if case let .text(t) = $0 { return t }
            return nil
        })

        #expect(text.contains("0 symbols"))
        #expect(text.contains("No symbols found."))
    }

    @Test
    func `Kind filter restricts to protocols only`() async throws {
        let result = try await tool.execute(arguments: [
            "module": .string("Testing"),
            "kind": .string("protocol"),
            "query": .string("Trait"),
        ])

        let text = try #require(result.content.first.flatMap {
            if case let .text(t) = $0 { return t }
            return nil
        })

        #expect(text.contains("protocol"))
        let lines = text.split(separator: "\n")
        for line in lines
            where line.hasPrefix("struct ") || line.hasPrefix("class ") || line.hasPrefix("enum ")
        {
            Issue.record("Found non-protocol symbol: \(line)")
        }
    }
}
