import MCP
import Testing
@testable import XCMCPCore

struct TestIdentifierNormalizationTests {
    @Test func `plain identifier unchanged`() {
        let params = makeParams(onlyTesting: ["AppTests/FooTests/testBar"])
        #expect(params.onlyTesting == ["AppTests/FooTests/testBar"])
    }

    @Test func `already backtick-wrapped unchanged`() {
        let params = makeParams(onlyTesting: [
            "AppTests/FooTests/`method with spaces`()",
        ])
        #expect(params.onlyTesting == [
            "AppTests/FooTests/`method with spaces`()",
        ])
    }

    @Test func `spaces without backticks get wrapped`() {
        let params = makeParams(onlyTesting: [
            "AppTests/TextViewCoordinatorSelectionTests/NSTextView shifts cursor when text inserted before cursor",
        ])
        #expect(params.onlyTesting == [
            "AppTests/TextViewCoordinatorSelectionTests/`NSTextView shifts cursor when text inserted before cursor`()",
        ])
    }

    @Test func `multiple identifiers normalized independently`() {
        let params = makeParams(onlyTesting: [
            "AppTests/FooTests/testPlain",
            "AppTests/BarTests/name with spaces",
            "AppTests/BazTests/`already wrapped`()",
        ])
        #expect(params.onlyTesting == [
            "AppTests/FooTests/testPlain",
            "AppTests/BarTests/`name with spaces`()",
            "AppTests/BazTests/`already wrapped`()",
        ])
    }

    @Test func `target-only identifier unchanged`() {
        let params = makeParams(onlyTesting: ["AppTests"])
        #expect(params.onlyTesting == ["AppTests"])
    }

    @Test func `target and class identifier unchanged`() {
        let params = makeParams(onlyTesting: ["AppTests/FooTests"])
        #expect(params.onlyTesting == ["AppTests/FooTests"])
    }

    @Test func `skip_testing also normalized`() {
        let params = makeParams(skipTesting: [
            "AppTests/FooTests/slow test method",
        ])
        #expect(params.skipTesting == [
            "AppTests/FooTests/`slow test method`()",
        ])
    }

    @Test func `spaces with trailing parens not doubled`() {
        let params = makeParams(onlyTesting: [
            "AppTests/FooTests/method name()",
        ])
        #expect(params.onlyTesting == [
            "AppTests/FooTests/`method name()`",
        ])
    }

    @Test func `swift keyword gets wrapped`() {
        let params = makeParams(onlyTesting: ["CoreTests/DiffTests/class"])
        #expect(params.onlyTesting == ["CoreTests/DiffTests/`class`()"])
    }

    @Test func `backtick-wrapped keyword without parens gets parens`() {
        let params = makeParams(onlyTesting: ["CoreTests/DiffTests/`class`"])
        #expect(params.onlyTesting == ["CoreTests/DiffTests/`class`()"])
    }

    @Test func `backtick-wrapped keyword with parens unchanged`() {
        let params = makeParams(onlyTesting: ["CoreTests/DiffTests/`class`()"])
        #expect(params.onlyTesting == ["CoreTests/DiffTests/`class`()"])
    }

    @Test func `non-keyword single word unchanged`() {
        let params = makeParams(onlyTesting: ["AppTests/FooTests/testBar"])
        #expect(params.onlyTesting == ["AppTests/FooTests/testBar"])
    }

    @Test func `multiple keywords normalized`() {
        let params = makeParams(onlyTesting: [
            "CoreTests/DiffTests/class",
            "CoreTests/DiffTests/import",
            "CoreTests/DiffTests/testRegular",
        ])
        #expect(params.onlyTesting == [
            "CoreTests/DiffTests/`class`()",
            "CoreTests/DiffTests/`import`()",
            "CoreTests/DiffTests/testRegular",
        ])
    }

    // MARK: - Helpers

    private func makeParams(
        onlyTesting: [String] = [],
        skipTesting: [String] = [],
    ) -> TestParameters {
        var args: [String: Value] = [:]
        if !onlyTesting.isEmpty {
            args["only_testing"] = .array(onlyTesting.map { .string($0) })
        }
        if !skipTesting.isEmpty {
            args["skip_testing"] = .array(skipTesting.map { .string($0) })
        }
        return args.testParameters()
    }
}
