import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

// MARK: - Slow integration tests (build+run+screenshot, preview capture)

/// Expensive integration tests that build, run, and screenshot full apps. Disabled by default — set
/// `RUN_SLOW_TESTS=1` to include.
@Suite(
    .enabled(
        if: IntegrationFixtures.simulatorAvailable
            && ProcessInfo.processInfo.environment["RUN_SLOW_TESTS"] != nil,
    ),
    .serialized,
    .temporaryDirectory,
)
struct SlowIntegrationTests {
    private let sessionManager = SessionManager()
    private let xcodebuildRunner = XcodebuildRunner()
    private let simctlRunner = SimctlRunner()

    // MARK: - IceCubesApp — build, run, screenshot (simulator)

    @Test(.timeLimit(.minutes(10)))
    func `build run screenshot ice cubes app sim`() async throws {
        let simulatorUDID = try #require(IntegrationFixtures.simulatorUDID)

        // 1. Boot simulator
        let bootTool = BootSimTool(simctlRunner: simctlRunner)
        _ = try await bootTool.execute(arguments: ["simulator": .string(simulatorUDID)])

        // 2. Build and run
        let buildRunTool = BuildRunSimTool(
            xcodebuildRunner: xcodebuildRunner,
            simctlRunner: simctlRunner,
            sessionManager: sessionManager,
        )
        let buildResult = try await buildRunTool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath),
            "scheme": .string("IceCubesApp"),
            "simulator": .string(simulatorUDID),
        ])

        let buildContent = textContent(buildResult)
        #expect(buildContent.contains("Successfully built and launched"))

        // 3. Wait for app to render. "Rendered" has no observable signal from outside the
        // simulator, so a poll has nothing to test and the wait stays fixed.
        try await Task.sleep(for: .seconds(3))

        // 4. Screenshot
        let savePath = TemporaryDirectory.url
            .appendingPathComponent("icecubes_screenshot.png").path
        let screenshotTool = ScreenshotTool(
            simctlRunner: simctlRunner,
            sessionManager: sessionManager,
        )
        let screenshotResult = try await screenshotTool.execute(arguments: [
            "simulator": .string(simulatorUDID),
            "output_path": .string(savePath),
        ])

        let screenshotContent = textContent(screenshotResult)
        #expect(screenshotContent.contains("Screenshot saved"))

        // 5. Verify PNG file exists
        #expect(FileManager.default.fileExists(atPath: savePath))

        // 6. Cleanup
        _ = try? await ProcessResult.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "terminate", simulatorUDID, "com.thomasricouard.IceCubesApp"],
        )
    }

    // MARK: - IceCubesApp — preview capture

    @Test(.timeLimit(.minutes(10)))
    func `preview capture ice cubes app`() async throws {
        let simulatorUDID = try #require(IntegrationFixtures.simulatorUDID)
        let pathUtility = PathUtility(
            basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false,
        )

        let tool = PreviewCaptureTool(
            xcodebuildRunner: xcodebuildRunner,
            simctlRunner: simctlRunner,
            pathUtility: pathUtility,
            sessionManager: sessionManager,
        )

        let result = try await tool.execute(arguments: [
            "file_path": .string(IntegrationFixtures.iceCubesPreviewFilePath),
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath),
            "simulator": .string(simulatorUDID),
        ])

        // Preview capture returns image content on success
        let hasImage = result.content.contains { item in
            if case .image = item { return true }
            return false
        }
        #expect(hasImage, "Expected preview capture to contain image content")
    }

    // MARK: - Helpers

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { item in
            if case let .text(text, _, _) = item { return text }
            return nil
        }.joined(separator: "\n")
    }
}

// MARK: - Build timeout output tests (real xcodebuild, short timeout)

/// Tests that build timeout output is unambiguous — agents must never see "Build succeeded" when
/// the build was interrupted by a timeout.
///
/// Builds ../thesis (sibling repo) with a 30s timeout to force a timeout/stuck error, then asserts
/// the formatted output says "Build interrupted" not "Build succeeded".
///
/// Disabled by default — set `RUN_SLOW_TESTS=1` to include.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["RUN_SLOW_TESTS"] != nil),
    .serialized,
)
struct BuildTimeoutOutputTests {
    private let xcodebuildRunner = XcodebuildRunner()
    private let sessionManager = SessionManager()

    /// Path to Thesis.xcodeproj (sibling repo).
    private static let thesisProjectPath: String = {
        let file = URL(fileURLWithPath: #filePath)
        return file
            .deletingLastPathComponent()  // Integration/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // xc-mcp/
            .deletingLastPathComponent()  // toba/
            .appendingPathComponent("thesis/Thesis.xcodeproj")
            .path
    }()

    static var thesisAvailable: Bool { FileManager.default.fileExists(atPath: thesisProjectPath) }

    @Test(.enabled(if: thesisAvailable), .timeLimit(.minutes(2)))
    func `Build timeout output never says Build succeeded`() async throws {
        let tool = BuildMacOSTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )

        // Disable sanitizers — TSan massively slows compilation and prevents the build from
        // reaching the phase where errors appear within the timeout.
        let result = try await tool.execute(arguments: [
            "project_path": .string(Self.thesisProjectPath),
            "scheme": .string("Standard"),
            "errors_only": .bool(true),
            "continue_building_after_errors": .bool(true),
            "timeout": .int(60),
            "build_settings": .object([
                "ENABLE_THREAD_SANITIZER": .string("NO"),
                "ENABLE_ADDRESS_SANITIZER": .string("NO"),
                "ENABLE_UNDEFINED_BEHAVIOR_SANITIZER": .string("NO"),
            ]),
        ])

        let text = result.content.compactMap { item -> String? in
            if case let .text(t, _, _) = item { return t }
            return nil
        }.joined(separator: "\n")

        print("--- Build timeout output ---")
        print(text)
        print("--- End output ---")

        // The tool returns isError=true on timeout
        #expect(result.isError == true)
        // Must say "interrupted", never "succeeded"
        #expect(text.contains("Build interrupted (did not complete)"))
        #expect(!text.contains("Build succeeded"))
        #expect(!text.contains("BUILD SUCCEEDED"))
        // Must have the timeout/stuck header
        let hasTimeoutHeader = text.contains("timed out") || text.contains("appears stuck")
        #expect(hasTimeoutHeader)
        // Must NOT dump build settings
        #expect(!text.contains("PRODUCT_NAME ="))
        #expect(!text.contains("PRODUCT_BUNDLE_IDENTIFIER ="))
    }
}
