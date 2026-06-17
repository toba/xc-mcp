import Testing
import Foundation
@testable import XCMCPCore

struct DerivedDataScoperTests {
    @Test func `scopedPath returns nil when neither workspace nor project provided`() {
        #expect(DerivedDataScoper.scopedPath(workspacePath: nil, projectPath: nil) == nil)
        #expect(DerivedDataScoper.scopedPath(workspacePath: "", projectPath: "") == nil)
    }

    @Test func `scopedPath uses workspace name when present`() {
        let path = DerivedDataScoper.scopedPath(
            workspacePath: "/Users/me/Developer/MyApp.xcworkspace",
            projectPath: "/Users/me/Developer/MyApp.xcodeproj",
        )
        #expect(path != nil)
        #expect(path?.contains("/MyApp-") == true)
        #expect(path?.contains("/Library/Caches/xc-mcp/DerivedData/") == true)
    }

    @Test func `scopedPath falls back to project when no workspace`() {
        let path = DerivedDataScoper.scopedPath(
            workspacePath: nil,
            projectPath: "/Users/me/Developer/MyApp.xcodeproj",
        )
        #expect(path?.contains("/MyApp-") == true)
    }

    @Test func `scopedPath is deterministic for same input`() {
        let p1 = DerivedDataScoper.scopedPath(
            workspacePath: "/Users/me/Developer/MyApp.xcworkspace", projectPath: nil,
        )
        let p2 = DerivedDataScoper.scopedPath(
            workspacePath: "/Users/me/Developer/MyApp.xcworkspace", projectPath: nil,
        )
        #expect(p1 == p2)
    }

    @Test func `scopedPath differs for different paths`() {
        let p1 = DerivedDataScoper.scopedPath(
            workspacePath: "/Users/me/clone-a/MyApp.xcworkspace", projectPath: nil,
        )
        let p2 = DerivedDataScoper.scopedPath(
            workspacePath: "/Users/me/clone-b/MyApp.xcworkspace", projectPath: nil,
        )
        #expect(p1 != p2)
    }

    @Test func `effectivePath returns nil when caller already passed -derivedDataPath`() {
        let path = DerivedDataScoper.effectivePath(
            workspacePath: "/Users/me/MyApp.xcworkspace",
            projectPath: nil,
            additionalArguments: ["-derivedDataPath", "/tmp/custom"],
        )
        #expect(path == nil)
    }

    @Test func `effectivePath honors XC_MCP_DISABLE_DERIVED_DATA_SCOPING`() {
        let path = DerivedDataScoper.effectivePath(
            workspacePath: "/Users/me/MyApp.xcworkspace",
            projectPath: nil,
            environment: ["XC_MCP_DISABLE_DERIVED_DATA_SCOPING": "1"],
        )
        #expect(path == nil)
    }

    @Test func `effectivePath ignores disable flag when 0 or false`() {
        let p1 = DerivedDataScoper.effectivePath(
            workspacePath: "/Users/me/MyApp.xcworkspace",
            projectPath: nil,
            environment: ["XC_MCP_DISABLE_DERIVED_DATA_SCOPING": "0"],
        )
        let p2 = DerivedDataScoper.effectivePath(
            workspacePath: "/Users/me/MyApp.xcworkspace",
            projectPath: nil,
            environment: ["XC_MCP_DISABLE_DERIVED_DATA_SCOPING": "false"],
        )
        #expect(p1 != nil)
        #expect(p2 != nil)
    }

    @Test func `effectivePath uses XC_MCP_DERIVED_DATA_PATH override`() {
        let path = DerivedDataScoper.effectivePath(
            workspacePath: "/Users/me/MyApp.xcworkspace",
            projectPath: nil,
            environment: ["XC_MCP_DERIVED_DATA_PATH": "/tmp/forced"],
        )
        #expect(path == "/tmp/forced")
    }

    @Test func `effectivePath returns nil when no project context`() {
        let path = DerivedDataScoper.effectivePath(
            workspacePath: nil, projectPath: nil, environment: [:],
        )
        #expect(path == nil)
    }

    // MARK: - Per-platform namespacing

    @Test func `platformSlug maps destinations to SDK-style slugs`() {
        #expect(DerivedDataScoper.platformSlug(forDestination: "platform=macOS") == "macosx")
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "platform=macOS,arch=arm64") == "macosx",
        )
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "platform=iOS Simulator,id=ABC")
                == "iphonesimulator",
        )
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "platform=iOS,id=ABC") == "iphoneos",
        )
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "generic/platform=iOS") == "iphoneos",
        )
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "platform=tvOS Simulator,id=X")
                == "appletvsimulator",
        )
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "platform=watchOS Simulator,id=X")
                == "watchsimulator",
        )
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "platform=visionOS Simulator,id=X")
                == "xrsimulator",
        )
        #expect(
            DerivedDataScoper.platformSlug(forDestination: "platform=macOS,variant=Mac Catalyst")
                == "maccatalyst",
        )
    }

    @Test func `platformSlug returns nil for nil empty or unknown destination`() {
        #expect(DerivedDataScoper.platformSlug(forDestination: nil) == nil)
        #expect(DerivedDataScoper.platformSlug(forDestination: "") == nil)
        #expect(DerivedDataScoper.platformSlug(forDestination: "platform=linux") == nil)
    }

    @Test func `scopedPath appends platform suffix for known destination`() {
        let macOS = DerivedDataScoper.scopedPath(
            workspacePath: nil,
            projectPath: "/Users/me/Developer/MyApp.xcodeproj",
            destination: "platform=macOS",
        )
        #expect(macOS?.hasSuffix("-macosx") == true)
        #expect(macOS?.contains("/MyApp-") == true)
    }

    @Test func `scopedPath without destination matches base path`() {
        let base = DerivedDataScoper.scopedPath(
            workspacePath: nil, projectPath: "/Users/me/Developer/MyApp.xcodeproj",
        )
        let nilDest = DerivedDataScoper.scopedPath(
            workspacePath: nil,
            projectPath: "/Users/me/Developer/MyApp.xcodeproj",
            destination: nil,
        )
        #expect(base == nilDest)
        #expect(base?.hasSuffix("-macosx") == false)
    }

    @Test func `scopedPath separates macOS from iOS-simulator for same project`() {
        let project = "/Users/me/Developer/Thesis.xcodeproj"
        let macOS = DerivedDataScoper.scopedPath(
            workspacePath: nil, projectPath: project, destination: "platform=macOS",
        )
        let sim = DerivedDataScoper.scopedPath(
            workspacePath: nil, projectPath: project,
            destination: "platform=iOS Simulator,id=ABC",
        )
        #expect(macOS != nil)
        #expect(sim != nil)
        #expect(macOS != sim)
        #expect(macOS?.hasSuffix("-macosx") == true)
        #expect(sim?.hasSuffix("-iphonesimulator") == true)
        // Same project hash, different platform suffix: shared prefix, divergent leaf.
        #expect(macOS?.contains("/Thesis-") == true)
        #expect(sim?.contains("/Thesis-") == true)
    }

    @Test func `effectivePath threads destination into scoped path`() {
        let path = DerivedDataScoper.effectivePath(
            workspacePath: nil,
            projectPath: "/Users/me/Developer/MyApp.xcodeproj",
            destination: "platform=iOS Simulator,id=ABC",
            environment: [:],
        )
        #expect(path?.hasSuffix("-iphonesimulator") == true)
    }
}
