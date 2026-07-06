import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct AuditSwiftPackagesToolTests {
    // MARK: - Helpers

    private func makeProject(
        packages: [(url: String, requirement: String)],
    ) throws -> (dir: URL, projectPath: Path) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

        for package in packages {
            _ = try addTool.execute(arguments: [
                "project_path": Value.string(projectPath.string),
                "package_url": Value.string(package.url),
                "requirement": Value.string(package.requirement),
            ])
        }
        return (tempDir, projectPath)
    }

    private func writeResolved(_ json: String, into projectPath: Path) throws {
        let dir = projectPath.string + "/project.xcworkspace/xcshareddata/swiftpm"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try json.write(toFile: dir + "/Package.resolved", atomically: true, encoding: .utf8)
    }

    private func run(_ projectPath: Path, base: String) throws -> String {
        let tool = AuditSwiftPackagesTool(pathUtility: PathUtility(basePath: base))
        let result = try tool.execute(arguments: ["project_path": Value.string(projectPath.string)])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return ""
        }
        return message
    }

    // MARK: - Tests

    @Test
    func `Tool metadata`() {
        let tool = AuditSwiftPackagesTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(tool.tool().name == "audit_swift_packages")
    }

    @Test
    func `Missing project path throws`() {
        let tool = AuditSwiftPackagesTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) { try tool.execute(arguments: [:]) }
    }

    @Test
    func `Missing Package.resolved and unstable pins are flagged`() throws {
        let (dir, projectPath) = try makeProject(packages: [
            (url: "https://github.com/Alamofire/Alamofire.git", requirement: "5.0.0"),
            (url: "https://github.com/apple/swift-collections.git", requirement: "branch: main"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let message = try run(projectPath, base: dir.path)

        #expect(message.contains("missingPackageResolved"))
        #expect(message.contains("exactVersion"))
        #expect(message.contains("alamofire"))
        #expect(message.contains("branchDependency"))
        #expect(message.contains("swift-collections"))
    }

    @Test
    func `Unresolved and stale pins are diffed against declarations`() throws {
        let (dir, projectPath) = try makeProject(packages: [
            (url: "https://github.com/Alamofire/Alamofire.git", requirement: "from: 5.0.0"),
            (url: "https://github.com/apple/swift-collections.git", requirement: "from: 1.0.0"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pins Alamofire (matched) + a stale package, and omits swift-collections (unresolved).
        try writeResolved(
            """
            {
              "pins": [
                {
                  "identity": "alamofire",
                  "kind": "remoteSourceControl",
                  "location": "https://github.com/Alamofire/Alamofire.git",
                  "state": { "revision": "abc", "version": "5.9.0" }
                },
                {
                  "identity": "swift-syntax",
                  "kind": "remoteSourceControl",
                  "location": "https://github.com/swiftlang/swift-syntax.git",
                  "state": { "revision": "def", "version": "600.0.0" }
                }
              ],
              "version": 2
            }
            """,
            into: projectPath,
        )

        let message = try run(projectPath, base: dir.path)

        #expect(!message.contains("missingPackageResolved"))
        #expect(message.contains("unresolvedReference"))
        #expect(message.contains("swift-collections"))
        #expect(message.contains("stalePin"))
        #expect(message.contains("swift-syntax"))
    }

    @Test
    func `Clean project with matching pins reports healthy`() throws {
        let (dir, projectPath) = try makeProject(packages: [
            (url: "https://github.com/Alamofire/Alamofire.git", requirement: "from: 5.0.0")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeResolved(
            """
            {
              "pins": [
                {
                  "identity": "alamofire",
                  "kind": "remoteSourceControl",
                  "location": "https://github.com/Alamofire/Alamofire.git",
                  "state": { "revision": "abc", "version": "5.9.0" }
                }
              ],
              "version": 2
            }
            """,
            into: projectPath,
        )

        let message = try run(projectPath, base: dir.path)
        #expect(message.contains("No dependency-health issues found"))
    }
}
