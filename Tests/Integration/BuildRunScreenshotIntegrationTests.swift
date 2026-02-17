import Foundation
import MCP
import Testing
import XCMCPCore

@testable import XCMCPTools

/// Integration tests that exercise build, run, screenshot, and preview capture
/// against real open-source repos.
/// Requires `scripts/fetch-fixtures.sh` to have been run first.
@Suite(.enabled(if: IntegrationFixtures.available))
struct BuildRunScreenshotIntegrationTests {

    // MARK: - Shared infrastructure

    private let sessionManager = SessionManager()
    private let xcodebuildRunner = XcodebuildRunner()
    private let simctlRunner = SimctlRunner()

    // MARK: - Alamofire — build only

    @Test(.enabled(if: IntegrationFixtures.simulatorAvailable), .timeLimit(.minutes(10)))
    func build_Alamofire_iOS() async throws {
        let tool = BuildSimTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
            "scheme": .string("Alamofire iOS"),
            "simulator": .string(IntegrationFixtures.simulatorUDID!),
        ])

        let content = textContent(result)
        #expect(content.contains("Build succeeded"))
    }

    @Test(.timeLimit(.minutes(10)))
    func build_Alamofire_macOS() async throws {
        let tool = BuildMacOSTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
            "scheme": .string("Alamofire macOS"),
        ])

        let content = textContent(result)
        #expect(content.contains("Build succeeded"))
    }

    // MARK: - SwiftFormat — build, run, screenshot (macOS)

    @Test(.timeLimit(.minutes(10)))
    func buildRunScreenshot_SwiftFormat_macOS() async throws {
        // 1. Build and run
        let buildRunTool = BuildRunMacOSTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager)
        let buildResult = try await buildRunTool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.swiftFormatProjectPath),
            "scheme": .string("SwiftFormat for Xcode"),
        ])

        let buildContent = textContent(buildResult)
        #expect(buildContent.contains("Successfully built and launched"))

        // 2. Wait for app to render
        try await Task.sleep(for: .seconds(3))

        // 3. Screenshot
        let savePath = NSTemporaryDirectory() + "swiftformat_screenshot_\(ProcessInfo.processInfo.globallyUniqueString).png"
        let screenshotTool = ScreenshotMacWindowTool()
        let screenshotResult = try await screenshotTool.execute(arguments: [
            "app_name": .string("SwiftFormat for Xcode"),
            "save_path": .string(savePath),
        ])

        // ScreenshotMacWindowTool returns image content
        let hasImage = screenshotResult.content.contains { item in
            if case .image = item { return true }
            return false
        }
        #expect(hasImage, "Expected screenshot to contain image content")

        // 4. Cleanup: kill the app
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-f", "SwiftFormat for Xcode"]
        try? killProcess.run()
        killProcess.waitUntilExit()

        // Clean up screenshot file
        try? FileManager.default.removeItem(atPath: savePath)
    }

    // MARK: - IceCubesApp — build, run, screenshot (simulator)

    @Test(.enabled(if: IntegrationFixtures.simulatorAvailable), .timeLimit(.minutes(10)))
    func buildRunScreenshot_IceCubesApp_sim() async throws {
        let simulatorUDID = IntegrationFixtures.simulatorUDID!

        // 1. Boot simulator
        let bootTool = BootSimTool(simctlRunner: simctlRunner)
        _ = try await bootTool.execute(arguments: [
            "simulator": .string(simulatorUDID)
        ])

        // 2. Build and run
        let buildRunTool = BuildRunSimTool(
            xcodebuildRunner: xcodebuildRunner,
            simctlRunner: simctlRunner,
            sessionManager: sessionManager)
        let buildResult = try await buildRunTool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath),
            "scheme": .string("IceCubesApp"),
            "simulator": .string(simulatorUDID),
        ])

        let buildContent = textContent(buildResult)
        #expect(buildContent.contains("Successfully built and launched"))

        // 3. Wait for app to render
        try await Task.sleep(for: .seconds(3))

        // 4. Screenshot
        let savePath = NSTemporaryDirectory() + "icecubes_screenshot_\(ProcessInfo.processInfo.globallyUniqueString).png"
        let screenshotTool = ScreenshotTool(
            simctlRunner: simctlRunner,
            sessionManager: sessionManager)
        let screenshotResult = try await screenshotTool.execute(arguments: [
            "simulator": .string(simulatorUDID),
            "output_path": .string(savePath),
        ])

        let screenshotContent = textContent(screenshotResult)
        #expect(screenshotContent.contains("Screenshot saved"))

        // 5. Verify PNG file exists
        #expect(FileManager.default.fileExists(atPath: savePath))

        // 6. Cleanup
        let terminateProcess = Process()
        terminateProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        terminateProcess.arguments = ["simctl", "terminate", simulatorUDID, "com.thomasricouard.IceCubesApp"]
        try? terminateProcess.run()
        terminateProcess.waitUntilExit()

        try? FileManager.default.removeItem(atPath: savePath)
    }

    // MARK: - IceCubesApp — preview capture

    @Test(.enabled(if: IntegrationFixtures.simulatorAvailable), .timeLimit(.minutes(10)))
    func previewCapture_IceCubesApp() async throws {
        let simulatorUDID = IntegrationFixtures.simulatorUDID!
        let pathUtility = PathUtility(
            basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false)

        let tool = PreviewCaptureTool(
            xcodebuildRunner: xcodebuildRunner,
            simctlRunner: simctlRunner,
            pathUtility: pathUtility,
            sessionManager: sessionManager)

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
            if case let .text(text) = item { return text }
            return nil
        }.joined(separator: "\n")
    }
}
