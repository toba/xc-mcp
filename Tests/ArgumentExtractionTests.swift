import MCP
import Testing
@testable import XCMCPCore

/// Covers the extractors that tool code calls in place of matching a `Value` case by hand.
@Suite
struct ArgumentExtractionTests {
    // MARK: - getNonEmptyString

    @Test
    func `getNonEmptyString returns nil for an empty string`() {
        let arguments: [String: Value] = ["filter": .string("")]
        #expect(arguments.getNonEmptyString("filter") == nil)
    }

    @Test
    func `getNonEmptyString returns the value for a non-empty string`() {
        let arguments: [String: Value] = ["filter": .string("App")]
        #expect(arguments.getNonEmptyString("filter") == "App")
    }

    @Test
    func `getNonEmptyString returns nil for a missing key`() {
        #expect([String: Value]().getNonEmptyString("filter") == nil)
    }

    // MARK: - getOptionalBool

    @Test
    func `getOptionalBool separates a false value from a missing key`() {
        let arguments: [String: Value] = ["glass": .bool(false)]
        #expect(arguments.getOptionalBool("glass") == false)
        #expect(arguments.getOptionalBool("specular") == nil)
    }

    @Test
    func `getOptionalBool returns nil for a non-boolean value`() {
        let arguments: [String: Value] = ["glass": .string("true")]
        #expect(arguments.getOptionalBool("glass") == nil)
    }

    // MARK: - getRequiredDouble

    @Test
    func `getRequiredDouble accepts an integer`() throws {
        let arguments: [String: Value] = ["x": .int(12)]
        #expect(try arguments.getRequiredDouble("x") == 12)
    }

    @Test
    func `getRequiredDouble throws when the key is missing`() {
        #expect(throws: MCPError.self) { try [String: Value]().getRequiredDouble("x") }
    }

    // MARK: - getOptionalStringArray

    @Test
    func `getOptionalStringArray separates an empty array from a missing key`() {
        let arguments: [String: Value] = ["input_paths": .array([])]
        #expect(arguments.getOptionalStringArray("input_paths") == [])
        #expect(arguments.getOptionalStringArray("output_paths") == nil)
    }

    @Test
    func `getOptionalStringArray drops non-string elements`() {
        let arguments: [String: Value] = ["files": .array([.string("a"), .int(1), .string("b")])]
        #expect(arguments.getOptionalStringArray("files") == ["a", "b"])
    }

    // MARK: - continueBuildingArgs

    @Test
    func `a build reports every failing target by default`() {
        #expect(
            [String: Value]().continueBuildingArgs()
                == ["-IDEBuildingContinueBuildingAfterErrors=YES"],
        )
    }

    @Test
    func `a build stops at the first error when the caller asks it to`() {
        let arguments: [String: Value] = ["continue_building_after_errors": .bool(false)]
        #expect(arguments.continueBuildingArgs().isEmpty)
    }
}
