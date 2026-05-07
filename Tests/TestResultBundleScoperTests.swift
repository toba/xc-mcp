import Testing
@testable import XCMCPCore
import Foundation

struct TestResultBundleScoperTests {
    @Test
    func `Managed path lives under the project-scoped TestResults directory`() {
        let env: [String: String] = ["XC_MCP_TEST_RESULTS_PATH": NSTemporaryDirectory() + "xc-mcp-scoper-test-\(UUID().uuidString)"]
        defer { try? FileManager.default.removeItem(atPath: env["XC_MCP_TEST_RESULTS_PATH"]!) }

        let path = TestResultBundleScoper.managedPath(
            workspacePath: nil,
            projectPath: "/tmp/Foo.xcodeproj",
            environment: env,
        )

        let scopedDir = TestResultBundleScoper.scopedDir(
            workspacePath: nil,
            projectPath: "/tmp/Foo.xcodeproj",
            environment: env,
        )!
        #expect(path.hasPrefix(scopedDir + "/"))
        #expect(path.hasSuffix(".xcresult"))
        // Parent directory of the bundle is created so xcodebuild can write into it.
        #expect(FileManager.default.fileExists(atPath: scopedDir))
    }

    @Test
    func `Same project path produces stable scoped directory`() {
        let dirA = TestResultBundleScoper.scopedDir(
            workspacePath: nil, projectPath: "/Users/example/Foo.xcodeproj",
        )
        let dirB = TestResultBundleScoper.scopedDir(
            workspacePath: nil, projectPath: "/Users/example/Foo.xcodeproj",
        )
        #expect(dirA == dirB)
        #expect(dirA?.contains("/Foo-") == true)
    }

    @Test
    func `Different project paths produce different scoped directories`() {
        let dirA = TestResultBundleScoper.scopedDir(
            workspacePath: nil, projectPath: "/Users/example/Foo.xcodeproj",
        )
        let dirB = TestResultBundleScoper.scopedDir(
            workspacePath: nil, projectPath: "/Users/other/Foo.xcodeproj",
        )
        #expect(dirA != dirB)
    }

    @Test
    func `Workspace path takes precedence over project path`() {
        let dir = TestResultBundleScoper.scopedDir(
            workspacePath: "/Users/example/Bar.xcworkspace",
            projectPath: "/Users/example/Foo.xcodeproj",
        )
        #expect(dir?.contains("/Bar-") == true)
        #expect(dir?.contains("/Foo-") == false)
    }

    @Test
    func `Returns nil scoped directory when no paths are provided`() {
        let dir = TestResultBundleScoper.scopedDir(workspacePath: nil, projectPath: nil)
        #expect(dir == nil)
    }

    @Test
    func `XC_MCP_TEST_RESULTS_PATH overrides the base directory`() {
        let env = ["XC_MCP_TEST_RESULTS_PATH": "/tmp/custom-results"]
        let dir = TestResultBundleScoper.scopedDir(
            workspacePath: nil,
            projectPath: "/Users/example/Foo.xcodeproj",
            environment: env,
        )
        #expect(dir?.hasPrefix("/tmp/custom-results/") == true)
    }

    @Test
    func `XC_MCP_DISABLE_TEST_RESULTS_SCOPING falls back to tmp`() {
        let env = ["XC_MCP_DISABLE_TEST_RESULTS_SCOPING": "1"]
        let path = TestResultBundleScoper.managedPath(
            workspacePath: nil,
            projectPath: "/Users/example/Foo.xcodeproj",
            environment: env,
        )
        #expect(path.contains("xc-mcp-test-"))
        #expect(path.hasSuffix(".xcresult"))
        // Sanity: the scoped cache directory should not be in the path.
        #expect(!path.contains("/Library/Caches/xc-mcp/TestResults/"))
    }

    @Test
    func `Pruning removes bundles older than retention but keeps fresh ones`() throws {
        let fm = FileManager.default
        let tmp = NSTemporaryDirectory()
            + "xc-mcp-scoper-prune-\(UUID().uuidString)"
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmp) }

        let oldBundle = "\(tmp)/old.xcresult"
        let freshBundle = "\(tmp)/fresh.xcresult"
        let unrelated = "\(tmp)/keep-me.txt"
        try fm.createDirectory(atPath: oldBundle, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: freshBundle, withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: unrelated))

        let now = Date()
        let oldDate = now.addingTimeInterval(-30 * 24 * 60 * 60)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldBundle)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: freshBundle)

        TestResultBundleScoper.pruneOldBundles(
            in: tmp,
            retention: 7 * 24 * 60 * 60,
            now: now,
        )

        #expect(!fm.fileExists(atPath: oldBundle))
        #expect(fm.fileExists(atPath: freshBundle))
        #expect(fm.fileExists(atPath: unrelated))
    }

    @Test
    func `Pruning is a no-op when the directory does not exist`() {
        // Should not throw or crash.
        TestResultBundleScoper.pruneOldBundles(
            in: "/nonexistent/path-\(UUID().uuidString)",
        )
    }
}

struct ErrorExtractorResultBundleSuffixTests {
    @Test
    func `Result bundle path is appended to passing test output when bundle exists`() async throws {
        let fm = FileManager.default
        let bundle = NSTemporaryDirectory()
            + "xc-mcp-suffix-\(UUID().uuidString).xcresult"
        try fm.createDirectory(atPath: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: bundle) }

        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            xcresultPath: bundle,
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(text.contains("Result bundle: \(bundle)"))
    }

    @Test
    func `Result bundle line is omitted when xcresult path is nil`() async throws {
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(!text.contains("Result bundle:"))
    }

    @Test
    func `Result bundle line is omitted when bundle file does not exist`() async throws {
        let result = try await ErrorExtractor.formatTestToolResult(
            output: "Test run with 1 test in 1 suite passed after 0.5 seconds",
            succeeded: true,
            context: "scheme 'Foo' on macOS",
            xcresultPath: "/nonexistent/path-\(UUID().uuidString).xcresult",
        )
        let text = result.content.compactMap {
            if case let .text(t, _, _) = $0 { return t }
            return nil
        }.joined()
        #expect(!text.contains("Result bundle:"))
    }

    @Test
    func `Result bundle path is appended to failure error when bundle exists`() async throws {
        let fm = FileManager.default
        let bundle = NSTemporaryDirectory()
            + "xc-mcp-suffix-fail-\(UUID().uuidString).xcresult"
        try fm.createDirectory(atPath: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: bundle) }

        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: """
                Test Case 'FooTests.testBar' failed (0.5 seconds)
                Executed 1 test, with 1 failure in 0.5 seconds
                """,
                succeeded: false,
                context: "scheme 'Foo' on macOS",
                xcresultPath: bundle,
            )
            Issue.record("Expected error to be thrown")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Result bundle: \(bundle)"))
        }
    }
}
