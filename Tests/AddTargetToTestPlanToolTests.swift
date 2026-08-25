import MCP
import PathKit
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct AddTargetToTestPlanToolTests {
    let pathUtility = PathUtility(basePath: "/")

    /// Creates a test project with a test target in the temporary directory of the test.
    private func createTempProject() throws -> String {
        let projectPath = Path(TemporaryDirectory.path) + "Test.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Test", targetName: "TestTarget", at: projectPath,
        )
        return projectPath.string
    }

    private func createTestPlan(_ json: [String: AnyValue]) throws -> String {
        let path = TemporaryDirectory.url.appendingPathComponent("test.xctestplan").path
        try TestPlanFile.write(json, to: path)
        return path
    }

    private func emptyPlan() -> [String: AnyValue] {
        [
            "configurations": [["id": "DEFAULT", "name": "Default", "options": [:]]],
            "defaultOptions": [:],
            "testTargets": [],
            "version": 1,
        ]
    }

    @Test func `adds target without selectedTests`() throws {
        let projectPath = try createTempProject()
        let path = try createTestPlan(emptyPlan())

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue ?? []
        #expect(targets.count == 1)
        #expect(targets[0]["selectedTests"] == nil)
    }

    @Test func `adds target with xctest_classes`() throws {
        let projectPath = try createTempProject()
        let path = try createTestPlan(emptyPlan())

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "xctest_classes": .array([
                .object(["name": .string("URLRequestTests")]),
                .object([
                    "name": .string("SessionTests"),
                    "xctest_methods": .array([.string("testInit()")]),
                ]),
            ]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue ?? []
        #expect(targets.count == 1)

        let selected = targets[0]["selectedTests"]?.dictionaryValue
        #expect(selected != nil)

        let classes = selected?["xctestClasses"]?.dictionaryArrayValue ?? []
        #expect(classes.count == 2)
        #expect(classes[0]["name"]?.stringValue == "URLRequestTests")
        #expect(classes[0]["xctestMethods"] == nil)
        #expect(classes[1]["name"]?.stringValue == "SessionTests")

        let methods = classes[1]["xctestMethods"]?.stringArrayValue ?? []
        #expect(methods == ["testInit()"])
    }

    @Test func `adds target with suites`() throws {
        let projectPath = try createTempProject()
        let path = try createTestPlan(emptyPlan())

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "suites": .array([
                .object([
                    "name": .string("NetworkTests"),
                    "test_functions": .array([.string("fetchKeys()"), .string("keys()")]),
                ]),
                .object(["name": .string("CacheTests")]),
            ]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue ?? []
        let selected = targets[0]["selectedTests"]?.dictionaryValue
        #expect(selected != nil)

        let suites = selected?["suites"]?.dictionaryArrayValue ?? []
        #expect(suites.count == 2)
        #expect(suites[0]["name"]?.stringValue == "NetworkTests")

        let funcs = suites[0]["testFunctions"]?.stringArrayValue ?? []
        #expect(funcs == ["fetchKeys()", "keys()"])
        #expect(suites[1]["name"]?.stringValue == "CacheTests")
        #expect(suites[1]["testFunctions"] == nil)
    }

    @Test func `adds target with both xctest_classes and suites`() throws {
        let projectPath = try createTempProject()
        let path = try createTestPlan(emptyPlan())

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "xctest_classes": .array([.object(["name": .string("PerfTests")])]),
            "suites": .array([.object(["name": .string("APISuite")])]),
        ])

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue ?? []
        let selected = targets[0]["selectedTests"]?.dictionaryValue
        #expect(selected != nil)

        let classes = selected?["xctestClasses"]?.dictionaryArrayValue ?? []
        let suites = selected?["suites"]?.dictionaryArrayValue ?? []
        #expect(classes.count == 1)
        #expect(suites.count == 1)
    }

    @Test func `selectedTests roundtrips through JSON`() throws {
        let projectPath = try createTempProject()
        let path = try createTestPlan(emptyPlan())

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "xctest_classes": .array([
                .object([
                    "name": .string("DecoderTests"),
                    "xctest_methods": .array([.string("testDecode()")]),
                ])
            ]),
            "suites": .array([
                .object([
                    "name": .string("ParserTests"),
                    "test_functions": .array([.string("parse()")]),
                ])
            ]),
        ])

        // Read the file with JSONSerialization rather than TestPlanFile, so the check proves the
        // bytes on disk are valid JSON and not that this server can read what it wrote
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(rawJSON != nil)

        let targets = rawJSON?["testTargets"] as? [[String: Any]] ?? []
        let selected = targets[0]["selectedTests"] as? [String: Any]
        #expect(selected?["xctestClasses"] != nil)
        #expect(selected?["suites"] != nil)
    }
}
