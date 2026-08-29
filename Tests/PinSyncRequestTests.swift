import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

@Suite("Pin sync request", .temporaryDirectory)
struct PinSyncRequestTests {
    static let inlineArguments: [String: Value] = [
        "members": .array([.string("/tmp/toba-core"), .string("/tmp/toba-hash")]),
        "updated": .array([
            .object(["package": .string("toba-core"), "version": .string("1.13.3")])
        ]),
    ]

    @Test func `reads members and updates from the arguments`() throws {
        let request = try PinSyncRequest.make(from: Self.inlineArguments)
        #expect(request.members.count == 2)
        #expect(
            request.updates == [.init(identity: "toba-core", version: SemanticVersion("1.13.3")!)])
    }

    @Test func `defaults to a dry run, a minor bump and the origin remote`() throws {
        let request = try PinSyncRequest.make(from: Self.inlineArguments)
        #expect(request.dryRun)
        #expect(request.bump == .minor)
        #expect(request.remote == "origin")
        #expect(request.noTag.isEmpty)
    }

    @Test func `reads an updated package given as a repository URL`() throws {
        let request = try PinSyncRequest.make(from: [
            "members": .array([.string("/tmp/toba-core")]),
            "updated": .array([
                .object([
                    "package": .string("https://github.com/toba/toba-core.git"),
                    "version": .string("2.0.0"),
                ])
            ]),
        ])
        #expect(request.updates[0].identity == "toba-core")
    }

    @Test func `refuses a version that is not semantic`() {
        #expect(throws: MCPError.self) {
            try PinSyncRequest.make(from: [
                "members": .array([.string("/tmp/toba-core")]),
                "updated": .array([
                    .object(["package": .string("toba-core"), "version": .string("latest")])
                ]),
            ])
        }
    }

    @Test func `refuses an empty member list`() {
        #expect(throws: MCPError.self) {
            try PinSyncRequest.make(from: [
                "updated": .array([
                    .object(["package": .string("toba-core"), "version": .string("1.0.0")])
                ])
            ])
        }
    }

    @Test func `refuses a plan that names no updated package`() {
        #expect(throws: MCPError.self) {
            try PinSyncRequest.make(from: ["members": .array([.string("/tmp/toba-core")])])
        }
    }

    @Test func `refuses an unknown bump policy`() {
        var arguments = Self.inlineArguments
        arguments["bump"] = .string("enormous")
        #expect(throws: MCPError.self) { try PinSyncRequest.make(from: arguments) }
    }

    @Test func `reads a plan from a JSON file`() throws {
        let path = TemporaryDirectory.path + "/plan.json"
        try """
        {
          "members": ["/tmp/toba-core", "/tmp/toba-hash", "/tmp/toba-data"],
          "updated": [{ "package": "toba-core", "version": "1.13.3" }],
          "bump": "patch",
          "dry_run": false,
          "no_tag": ["thesis"],
          "remote": "upstream"
        }
        """.write(toFile: path, atomically: true, encoding: .utf8)

        let request = try PinSyncRequest.make(from: ["plan_path": .string(path)])
        #expect(request.members.count == 3)
        #expect(request.bump == .patch)
        #expect(!request.dryRun)
        #expect(request.noTag == ["thesis"])
        #expect(request.remote == "upstream")
    }

    @Test func `lets an inline argument win over the file`() throws {
        let path = TemporaryDirectory.path + "/plan.json"
        try """
        {
          "members": ["/tmp/toba-core"],
          "updated": [{ "package": "toba-core", "version": "1.0.0" }],
          "bump": "patch"
        }
        """.write(toFile: path, atomically: true, encoding: .utf8)

        let request = try PinSyncRequest.make(from: [
            "plan_path": .string(path), "bump": .string("major"),
        ])
        #expect(request.bump == .major)
        #expect(request.updates[0].version == SemanticVersion("1.0.0"))
    }

    @Test func `refuses a plan file it cannot read`() {
        #expect(throws: MCPError.self) {
            try PinSyncRequest.make(from: ["plan_path": .string(TemporaryDirectory.path + "/gone")])
        }
    }
}
