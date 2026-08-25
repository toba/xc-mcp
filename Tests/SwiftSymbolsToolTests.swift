import MCP
import Testing
import Foundation
@testable import XCMCPTools

struct SwiftSymbolsToolTests {
    private let tool = SwiftSymbolsTool()

    /// The root of this package, the directory that holds `Package.swift`.
    ///
    /// The tests that resolve a package module read the build output of this package itself. A test
    /// run always leaves that output in place, so no test has to build anything.
    private var packageRoot: String {
        // #filePath → …/Tests/SwiftSymbolsToolTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    /// The text of the first content block, or a recorded failure.
    private func text(of result: CallTool.Result) throws -> String {
        try #require(
            result.content.first.flatMap {
                if case let .text(t, _, _) = $0 { return t }
                return nil
            },
        )
    }

    // MARK: - Tool metadata

    @Test
    func `Tool name and description are correct`() {
        let definition = tool.tool()
        #expect(definition.name == "swift_symbols")
        #expect(definition.description?.contains("swift-symbolgraph-extract") == true)
    }

    @Test
    func `Schema offers a project path`() throws {
        let definition = tool.tool()
        guard case let .object(schema) = definition.inputSchema,
              case let .object(properties)? = schema["properties"]
        else {
            Issue.record("Input schema has no properties object")
            return
        }
        #expect(properties["project_path"] != nil)
    }

    // MARK: - Missing required parameter

    @Test
    func `Missing module parameter throws invalidParams`() async {
        await #expect(throws: MCPError.self) { try await tool.execute(arguments: [:]) }
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

    @Test(.timeLimit(.minutes(5)))
    func `Extract Testing module and find Trait protocol`() async throws {
        let result = try await tool.execute(arguments: [
            "module": .string("Testing"),
            "query": .string("Trait"),
        ])

        let text = try #require(
            result.content.first.flatMap {
                if case let .text(t, _, _) = $0 { return t }
                return nil
            },
        )

        #expect(text.contains("Module: Testing"))
        #expect(text.lowercased().contains("trait"))
    }

    @Test(.timeLimit(.minutes(5)))
    func `Query with no matches returns empty result`() async throws {
        let result = try await tool.execute(arguments: [
            "module": .string("Testing"),
            "query": .string("xyzzy_nonexistent_symbol_12345"),
        ])

        let text = try #require(
            result.content.first.flatMap {
                if case let .text(t, _, _) = $0 { return t }
                return nil
            },
        )

        #expect(text.contains("0 symbols"))
        #expect(text.contains("No symbols found."))
    }

    @Test(.timeLimit(.minutes(5)))
    func `Kind filter restricts to protocols only`() async throws {
        let result = try await tool.execute(arguments: [
            "module": .string("Testing"),
            "kind": .string("protocol"),
            "query": .string("Trait"),
        ])

        let text = try #require(
            result.content.first.flatMap {
                if case let .text(t, _, _) = $0 { return t }
                return nil
            },
        )

        #expect(text.contains("protocol"))
        let lines = text.split(separator: "\n")
        for line in lines
            where line.hasPrefix("struct ") || line.hasPrefix("class ") || line.hasPrefix("enum ")
        { Issue.record("Found non-protocol symbol: \(line)") }
    }

    // MARK: - Package modules

    @Test(.timeLimit(.minutes(5)))
    func `Project path resolves a module built by that package`() async throws {
        let result = try await tool.execute(arguments: [
            "module": .string("OrderedCollections"),
            "project_path": .string(packageRoot),
            "query": .string("OrderedSet"),
        ])

        let output = try text(of: result)
        #expect(output.contains("Module: OrderedCollections"))
        #expect(output.contains("Package module search:"))
        #expect(output.contains("OrderedSet"))
    }

    @Test(.timeLimit(.minutes(5)))
    func `The same module fails without a project path`() async {
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "module": .string("OrderedCollections"),
                "query": .string("OrderedSet"),
            ])
        }
    }

    @Test(.timeLimit(.minutes(5)))
    func `A module in neither the SDK nor the package fails`() async {
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "module": .string("NoSuchModule_xcmcp_12345"),
                "project_path": .string(packageRoot),
            ])
        }
    }

    // MARK: - Missing module report

    /// The description of the error `execute` throws for a module that cannot load.
    private func failureMessage(module: String) async -> String {
        do {
            _ = try await tool.execute(arguments: ["module": .string(module)])
        } catch {
            return "\(error)"
        }
        Issue.record("Expected module '\(module)' to fail")
        return ""
    }

    /// The names on the `Closest visible modules:` line of a failure message.
    private func closestModules(in message: String) throws -> [String] {
        let prefix = "Closest visible modules: "
        let line = try #require(message.split(separator: "\n").first { $0.hasPrefix(prefix) })
        return line.dropFirst(prefix.count).components(separatedBy: ", ")
    }

    @Test(.timeLimit(.minutes(5)))
    func `A missing module reports at most ten candidates`() async throws {
        let message = await failureMessage(module: "OrderedCollections")
        let candidates = try closestModules(in: message)

        #expect(!candidates.isEmpty)
        #expect(candidates.count <= 10)
        // the compiler's own list of every visible module stays out of the reply
        #expect(!message.contains("Current visible modules:"))
    }

    @Test(.timeLimit(.minutes(5)))
    func `A missing module reply names the next action`() async {
        let message = await failureMessage(module: "OrderedCollections")

        #expect(message.contains("Module 'OrderedCollections' is not in the macos SDK."))
        #expect(message.contains("project_path"))
    }

    @Test(.timeLimit(.minutes(5)))
    func `A project path with no build output reports the missing build`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect {
            try await tool.execute(arguments: [
                "module": .string("NoSuchModule_xcmcp_12345"),
                "project_path": .string(directory.path),
            ])
        } throws: { error in "\(error)".contains("Build the package first") }
    }
}
