import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct SetTestPlanSkippedTestsToolTests {
    private let pathUtility = PathUtility(basePath: TemporaryDirectory.path)

    private func createTestPlan(_ json: [String: AnyValue]) throws -> String {
        let path = TemporaryDirectory.url.appendingPathComponent("test.xctestplan").path
        try TestPlanFile.write(json, to: path)
        return path
    }

    private func basePlan() -> [String: AnyValue] {
        [
            "configurations": [["id": "DEFAULT", "name": "Default", "options": [:]]],
            "defaultOptions": [:],
            "testTargets": [
                [
                    "target": [
                        "containerPath": "container:App.xcodeproj",
                        "identifier": "ABC123",
                        "name": "AppTests",
                    ]
                ]
            ],
            "version": 1,
        ]
    }

    @Test
    func `Tool schema has correct name`() {
        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let schema = tool.tool()
        #expect(schema.name == "set_test_plan_skipped_tests")
    }

    @Test
    func `Add tests to plan-level defaults`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([
                .string("PerfTests"),
                .string("XMLDecoderPerformanceTests/testDecode()"),
            ]),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))
        #expect(message.contains("plan-level defaults"))

        let json = try TestPlanFile.read(from: path)
        let defaults = json["defaultOptions"]?.dictionaryValue
        let tests = defaults?["skippedTests"]?.stringArrayValue
        #expect(tests == ["PerfTests", "XMLDecoderPerformanceTests/testDecode()"])
    }

    @Test
    func `Add tests to specific target`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests")]),
            "target_name": .string("AppTests"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("target 'AppTests'"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue
        let tests = targets?.first?["skippedTests"]?.stringArrayValue
        #expect(tests == ["PerfTests"])
    }

    @Test
    func `Remove tests from plan-level defaults`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"]?.dictionaryValue)
        defaults["skippedTests"] = ["PerfTests", "SlowTests", "FlakyTests"]
        plan["defaultOptions"] = .dictionary(defaults)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests"), .string("SlowTests")]),
            "action": .string("remove"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Removed"))

        let json = try TestPlanFile.read(from: path)
        let tests = (json["defaultOptions"]?.dictionaryValue)?["skippedTests"]?.stringArrayValue
        #expect(tests == ["FlakyTests"])
    }

    @Test
    func `Remove all tests clears skippedTests key`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"]?.dictionaryValue)
        defaults["skippedTests"] = ["PerfTests"]
        plan["defaultOptions"] = .dictionary(defaults)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests")]),
            "action": .string("remove"),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let tests = (json["defaultOptions"]?.dictionaryValue)?["skippedTests"]
        #expect(tests == nil)
    }

    @Test
    func `Add duplicate tests is idempotent`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"]?.dictionaryValue)
        defaults["skippedTests"] = ["PerfTests"]
        plan["defaultOptions"] = .dictionary(defaults)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests"), .string("SlowTests")]),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let tests = (json["defaultOptions"]?.dictionaryValue)?["skippedTests"]?.stringArrayValue
        #expect(tests == ["PerfTests", "SlowTests"])
    }

    @Test
    func `Target not found throws error`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests")]),
            "target_name": .string("NonExistent"),
        ]
        #expect(throws: MCPError.self) { try tool.execute(arguments: args) }
    }

    @Test
    func `Empty tests array throws error`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = ["test_plan_path": .string(path), "tests": .array([])]
        #expect(throws: MCPError.self) { try tool.execute(arguments: args) }
    }

    // MARK: - Dictionary shape

    /// Builds the nested shape Xcode writes for Swift Testing suites.
    ///
    /// The value holds 10 leaf entries. The first suite holds 2 nested suites and 3 test functions.
    /// The second holds 2 test functions. The third names a whole suite. The XCTest class holds 2
    /// methods.
    private func nestedSkippedTests() -> [String: AnyValue] {
        let attributedString: [String: AnyValue] = [
            "name": "AttributedStringExtensionsTests",
            "suites": [
                ["name": "fancyQuotes(rawText:rawExpect:)"],
                ["name": "plainTextJsonCodable(given:expect:)"],
            ],
            "testFunctions": ["jsonDecode()", "jsonEncode()", "trimEnd()"],
        ]
        let bibliography: [String: AnyValue] = [
            "name": "BibliographyTests",
            "testFunctions": ["defaultSort()", "nameSort()"],
        ]
        let xmlDecoder: [String: AnyValue] = ["name": "XMLDecoderTests"]
        let legacy: [String: AnyValue] = [
            "name": "LegacyTests",
            "xctestMethods": ["testOne()", "testTwo()"],
        ]
        return [
            "suites": [
                .dictionary(attributedString), .dictionary(bibliography), .dictionary(xmlDecoder),
            ],
            "xctestClasses": [.dictionary(legacy)],
        ]
    }

    private func planWithNestedSkippedTests() -> [String: AnyValue] {
        var plan = basePlan()
        var targets = plan["testTargets"]?.dictionaryArrayValue ?? []
        targets[0]["skippedTests"] = .dictionary(nestedSkippedTests())
        plan["testTargets"] = .dictionaries(targets)
        return plan
    }

    private func skippedTestsDictionary(at path: String) throws -> [String: AnyValue] {
        let json = try TestPlanFile.read(from: path)
        let targets = try #require(json["testTargets"]?.dictionaryArrayValue)
        return try #require(targets.first?["skippedTests"]?.dictionaryValue)
    }

    private func execute(
        path: String,
        tests: [String],
        action: String,
        targetName: String? = "AppTests",
    ) throws -> String {
        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        var args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array(tests.map { .string($0) }),
            "action": .string(action),
        ]
        if let targetName { args["target_name"] = .string(targetName) }
        let result = try tool.execute(arguments: args)
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return message
    }

    @Test
    func `Remove one suite keeps every sibling in nested skippedTests`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(path: path, tests: ["XMLDecoderTests"], action: "remove")

        let skipped = try skippedTestsDictionary(at: path)
        let suites = try #require(skipped["suites"]?.dictionaryArrayValue)
        #expect(suites.count == 2)
        #expect(
            suites.map { $0["name"]?.stringValue } == [
                "AttributedStringExtensionsTests", "BibliographyTests",
            ])

        let first = try #require(suites.first)
        #expect((first["suites"]?.dictionaryArrayValue)?.count == 2)
        #expect(
            first["testFunctions"]?
                .stringArrayValue == ["jsonDecode()", "jsonEncode()", "trimEnd()"])
        #expect((skipped["xctestClasses"]?.dictionaryArrayValue)?.count == 1)
    }

    @Test
    func `Remove reports the entry count before and after`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        let message = try execute(path: path, tests: ["XMLDecoderTests"], action: "remove")

        // 5 entries under the first suite, 2 under the second, 1 leaf suite, 2 XCTest methods.
        #expect(message.contains("entries: 10 → 9"))
        #expect(!message.contains("no skipped tests remaining"))
    }

    @Test
    func `Remove a nested suite by path keeps the parent`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(
            path: path,
            tests: ["AttributedStringExtensionsTests/fancyQuotes(rawText:rawExpect:)"],
            action: "remove",
        )

        let skipped = try skippedTestsDictionary(at: path)
        let suites = try #require(skipped["suites"]?.dictionaryArrayValue)
        #expect(suites.count == 3)
        let parent = try #require(suites.first)
        let children = try #require(parent["suites"]?.dictionaryArrayValue)
        #expect(children.map { $0["name"]?.stringValue } == ["plainTextJsonCodable(given:expect:)"])
        #expect(
            parent["testFunctions"]?
                .stringArrayValue == ["jsonDecode()", "jsonEncode()", "trimEnd()"])
    }

    @Test
    func `Remove a test function keeps its parent suite`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(path: path, tests: ["BibliographyTests/defaultSort()"], action: "remove")

        let skipped = try skippedTestsDictionary(at: path)
        let suites = try #require(skipped["suites"]?.dictionaryArrayValue)
        #expect(suites.count == 3)
        let bibliography = try #require(suites.first {
            $0["name"]?.stringValue == "BibliographyTests"
        })
        #expect(bibliography["testFunctions"]?.stringArrayValue == ["nameSort()"])
    }

    @Test
    func `Remove the last test function drops the suite node`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(
            path: path,
            tests: ["BibliographyTests/defaultSort()", "BibliographyTests/nameSort()"],
            action: "remove",
        )

        let skipped = try skippedTestsDictionary(at: path)
        let suites = try #require(skipped["suites"]?.dictionaryArrayValue)
        #expect(
            suites.map { $0["name"]?.stringValue } == [
                "AttributedStringExtensionsTests", "XMLDecoderTests",
            ])
    }

    @Test
    func `Remove an XCTest method keeps its class`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(path: path, tests: ["LegacyTests/testOne()"], action: "remove")

        let skipped = try skippedTestsDictionary(at: path)
        let classes = try #require(skipped["xctestClasses"]?.dictionaryArrayValue)
        #expect(classes.count == 1)
        #expect(classes.first?["xctestMethods"]?.stringArrayValue == ["testTwo()"])
    }

    @Test
    func `Remove an absent entry reports no match and changes nothing`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        let message = try execute(path: path, tests: ["NotThere"], action: "remove")

        #expect(message.contains("no matching entry for 'NotThere'"))
        #expect(message.contains("entries: 10 → 10"))
        let skipped = try skippedTestsDictionary(at: path)
        #expect((skipped["suites"]?.dictionaryArrayValue)?.count == 3)
    }

    @Test
    func `Remove every entry drops the nested skippedTests key`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(
            path: path,
            tests: [
                "AttributedStringExtensionsTests",
                "BibliographyTests",
                "XMLDecoderTests",
                "LegacyTests",
            ],
            action: "remove",
        )

        let json = try TestPlanFile.read(from: path)
        let targets = try #require(json["testTargets"]?.dictionaryArrayValue)
        #expect(targets.first?["skippedTests"] == nil)
    }

    @Test
    func `Add a suite keeps the dictionary shape`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(path: path, tests: ["NewSuiteTests"], action: "add")

        let skipped = try skippedTestsDictionary(at: path)
        let suites = try #require(skipped["suites"]?.dictionaryArrayValue)
        #expect(suites.count == 4)
        #expect(suites.last?["name"]?.stringValue == "NewSuiteTests")
        #expect((skipped["xctestClasses"]?.dictionaryArrayValue)?.count == 1)
    }

    @Test
    func `Add a test function extends its suite`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(path: path, tests: ["BibliographyTests/extraSort()"], action: "add")

        let skipped = try skippedTestsDictionary(at: path)
        let suites = try #require(skipped["suites"]?.dictionaryArrayValue)
        let bibliography = try #require(suites.first {
            $0["name"]?.stringValue == "BibliographyTests"
        })
        #expect(
            bibliography["testFunctions"]?
                .stringArrayValue
                == ["defaultSort()", "nameSort()", "extraSort()"])
    }

    @Test
    func `Add a whole suite replaces its narrower entries`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(path: path, tests: ["BibliographyTests"], action: "add")

        let skipped = try skippedTestsDictionary(at: path)
        let suites = try #require(skipped["suites"]?.dictionaryArrayValue)
        let bibliography = try #require(suites.first {
            $0["name"]?.stringValue == "BibliographyTests"
        })
        #expect(bibliography["testFunctions"] == nil)
        #expect(bibliography.count == 1)
    }

    @Test
    func `Add an XCTest method extends its class`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        _ = try execute(path: path, tests: ["LegacyTests/testThree()"], action: "add")

        let skipped = try skippedTestsDictionary(at: path)
        let classes = try #require(skipped["xctestClasses"]?.dictionaryArrayValue)
        #expect(
            classes.first?["xctestMethods"]?
                .stringArrayValue
                == ["testOne()", "testTwo()", "testThree()"])
        #expect((skipped["suites"]?.dictionaryArrayValue)?.count == 3)
    }

    @Test
    func `Add an entry that is already skipped reports it`() throws {
        let path = try createTestPlan(planWithNestedSkippedTests())

        let message = try execute(path: path, tests: ["XMLDecoderTests"], action: "add")

        #expect(message.contains("already skipped: 'XMLDecoderTests'"))
        #expect(message.contains("entries: 10 → 10"))
    }

    @Test
    func `Nested remove works at plan-level defaults`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"]?.dictionaryValue)
        defaults["skippedTests"] = .dictionary(nestedSkippedTests())
        plan["defaultOptions"] = .dictionary(defaults)
        let path = try createTestPlan(plan)

        _ = try execute(path: path, tests: ["XMLDecoderTests"], action: "remove", targetName: nil)

        let json = try TestPlanFile.read(from: path)
        let skipped = try #require(
            (json["defaultOptions"]?.dictionaryValue)?["skippedTests"]?.dictionaryValue,
        )
        #expect((skipped["suites"]?.dictionaryArrayValue)?.count == 2)
    }

    @Test
    func `Unknown keys in the nested value survive a remove`() throws {
        var plan = basePlan()
        var targets = try #require(plan["testTargets"]?.dictionaryArrayValue)
        var skipped = nestedSkippedTests()
        skipped["futureXcodeKey"] = ["keep": "me"]
        targets[0]["skippedTests"] = .dictionary(skipped)
        plan["testTargets"] = .dictionaries(targets)
        let path = try createTestPlan(plan)

        _ = try execute(path: path, tests: ["XMLDecoderTests"], action: "remove")

        let result = try skippedTestsDictionary(at: path)
        #expect(result["futureXcodeKey"] == ["keep": "me"])
    }
}
