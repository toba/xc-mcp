import Foundation
import Testing
import XCMCPCore
@testable import XCMCPTools

struct ListTestPlanTargetsToolTests {
    private func makeTool() -> ListTestPlanTargetsTool {
        ListTestPlanTargetsTool(sessionManager: SessionManager())
    }

    private func createTestPlan(at directory: URL, name: String, targets: [String]) throws {
        let testTargets = targets.map { name in
            """
            {"target": {"name": "\(name)"}}
            """
        }
        let json = """
        {"testTargets": [\(testTargets.joined(separator: ","))]}
        """
        let filePath = directory.appendingPathComponent("\(name).xctestplan")
        try json.write(to: filePath, atomically: true, encoding: .utf8)
    }

    @Test func findTargetsWithAbsoluteSearchRoot() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createTestPlan(at: tempDir, name: "MyTests", targets: ["AppTests", "UITests"])

        let tool = makeTool()
        let targets = tool.findTestPlanTargets(planName: "MyTests", searchRoot: tempDir.path)
        #expect(targets == ["AppTests", "UITests"])
    }

    @Test func findTargetsWithDotSearchRoot() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createTestPlan(at: tempDir, name: "MyTests", targets: ["AppTests"])

        // Change to the temp directory and use "." as search root
        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDir.path)
        defer { FileManager.default.changeCurrentDirectoryPath(originalDir) }

        let tool = makeTool()
        let targets = tool.findTestPlanTargets(planName: "MyTests", searchRoot: ".")
        #expect(targets == ["AppTests"])
    }

    @Test func findTargetsWithEmptySearchRootReturnsEmpty() {
        let tool = makeTool()
        // Empty string returns nil enumerator, so no targets found
        let targets = tool.findTestPlanTargets(planName: "MyTests", searchRoot: "")
        #expect(targets.isEmpty)
    }

    @Test func findTargetsInSubdirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        let subDir = tempDir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createTestPlan(at: subDir, name: "DeepPlan", targets: ["DeepTests"])

        let tool = makeTool()
        let targets = tool.findTestPlanTargets(planName: "DeepPlan", searchRoot: tempDir.path)
        #expect(targets == ["DeepTests"])
    }
}
