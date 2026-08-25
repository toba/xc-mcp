import Testing
import Foundation
import XCMCPCore
import XCMCPTools

@Suite("Tool registry")
struct ToolRegistryTests {
    @Test("Every tool name is registered once")
    func namesAreUnique() {
        var seen = Set<String>()
        for registration in ToolRegistry.all {
            #expect(seen.insert(registration.name).inserted, "duplicate tool: \(registration.name)")
        }
    }

    @Test("Every registration names at least one server")
    func everyToolHasAServer() {
        for registration in ToolRegistry.all {
            #expect(!registration.servers.isEmpty, "no server hosts \(registration.name)")
        }
    }

    @Test("Every registered tool resolves a directory entry")
    func directoryCoversEveryTool() {
        // A tool absent from the directory makes the cross-server hint return nil, which is the
        // drift the hand-maintained name lists used to carry.
        for registration in ToolRegistry.all {
            let others = ServerSet.allFocused.union(.monolith).subtracting(registration.servers)
            guard !others.isEmpty else { continue }
            let hint = ServerToolDirectory.hint(
                for: registration.name, currentServer: others,
            )
            #expect(hint != nil, "no directory entry for \(registration.name)")
        }
    }

    @Test("The directory reports no hint for a tool the caller already hosts")
    func noHintForOwnTool() {
        for registration in ToolRegistry.all {
            #expect(
                ServerToolDirectory.hint(
                    for: registration.name, currentServer: registration.servers,
                ) == nil,
                "\(registration.name) hints at a server that already hosts it",
            )
        }
    }

    @Test("The directory reports no hint for an unknown name")
    func noHintForUnknownName() {
        #expect(ServerToolDirectory.hint(for: "not_a_tool", currentServer: .monolith) == nil)
    }

    @Test("Every focused-server tool is reachable from the monolith")
    func monolithReachesEveryFocusedTool() {
        // The xcstrings tools are deliberately exclusive to xc-strings. Every other focused tool
        // must also answer on the monolith.
        for registration in ToolRegistry.all where registration.servers != [.strings] {
            #expect(
                registration.servers.contains(.monolith),
                "the monolith cannot reach \(registration.name)",
            )
        }
    }

    @Test("Each server selects the tools it hosts")
    func registrationsFilterByServer() {
        for server in ServerSet.allFocused.union(.monolith).members {
            let hosted = ToolRegistry.registrations(for: server)
            #expect(!hosted.isEmpty, "\(server.executableName ?? "?") hosts no tool")
            for registration in hosted {
                #expect(registration.servers.contains(server))
            }
        }
    }

    @Test("Building a tool yields a descriptor whose name matches its registration")
    func descriptorNamesMatch() {
        let deps = ToolDeps(basePath: FileManager.default.currentDirectoryPath)
        for registration in ToolRegistry.all {
            #expect(registration.build(deps).descriptor.name == registration.name)
        }
    }
}
