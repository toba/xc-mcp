import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

// MARK: - Key / Symbol Naming

struct LocalizableKeyNamingTests {
    @Test func `screaming snake from plain word`() {
        #expect(LocalizableKeyNaming.screamingSnakeKey(from: "Cancel") == "CANCEL")
    }

    @Test func `screaming snake from phrase`() {
        #expect(LocalizableKeyNaming.screamingSnakeKey(from: "None Selected") == "NONE_SELECTED")
        #expect(
            LocalizableKeyNaming.screamingSnakeKey(
                from: "Add Citation To Group")
                == "ADD_CITATION_TO_GROUP",
        )
    }

    @Test func `screaming snake collapses punctuation and trims`() {
        #expect(
            LocalizableKeyNaming.screamingSnakeKey(from: "Domestic / Foreign") == "DOMESTIC_FOREIGN"
        )
        #expect(LocalizableKeyNaming.screamingSnakeKey(from: "  Save…  ") == "SAVE")
    }

    @Test func `screaming snake prefixes leading digit`() {
        #expect(LocalizableKeyNaming.screamingSnakeKey(from: "2 items") == "_2_ITEMS")
    }

    @Test func `screaming snake falls back for symbol-only value`() {
        #expect(LocalizableKeyNaming.screamingSnakeKey(from: "—") == "KEY")
    }

    @Test func `generated symbol camel cases key`() {
        #expect(LocalizableKeyNaming.generatedSymbol(forKey: "CANCEL") == "cancel")
        #expect(LocalizableKeyNaming.generatedSymbol(forKey: "NONE_SELECTED") == "noneSelected")
        #expect(
            LocalizableKeyNaming.generatedSymbol(
                forKey: "ADD_CITATION_TO_GROUP")
                == "addCitationToGroup",
        )
    }

    @Test func `generated symbol handles space-separated keys`() {
        #expect(LocalizableKeyNaming.generatedSymbol(forKey: "None Selected") == "noneSelected")
    }

    @Test func `generated symbol backticks keywords`() {
        #expect(LocalizableKeyNaming.generatedSymbol(forKey: "IMPORT") == "`import`")
        #expect(LocalizableKeyNaming.generatedSymbol(forKey: "RETURN") == "`return`")
    }

    @Test func `signature nil for plain value`() {
        #expect(LocalizableKeyNaming.generatedSignature(forKey: "CANCEL", value: "Cancel") == nil)
    }

    @Test func `signature for named placeholder`() {
        let signature = LocalizableKeyNaming.generatedSignature(
            forKey: "ADD_CITATION_TO_GROUP", value: "Add %1$(ordinal)@ citation",
        )
        #expect(signature == "addCitationToGroup(ordinal: String)")
    }

    @Test func `signature for positional placeholders`() {
        let signature = LocalizableKeyNaming.generatedSignature(
            forKey: "MOVED_N_OF_M", value: "Moved %1$lld of %2$lld",
        )
        #expect(signature == "movedNOfM(_ arg1: Int, _ arg2: Int)")
    }

    @Test func `key derivation strips placeholders`() {
        #expect(
            LocalizableKeyNaming.screamingSnakeKey(
                from: "Add %1$(ordinal)@ citation")
                == "ADD_CITATION",
        )
        #expect(LocalizableKeyNaming.screamingSnakeKey(from: "Delete %lld items") == "DELETE_ITEMS")
    }
}

// MARK: - Promote Literals

struct XCStringsPromoteLiteralsToolTests {
    private static func makeFile(at path: String, strings: [String: StringEntry] = [:]) throws {
        let file = XCStringsFile(sourceLanguage: "en", strings: strings, version: "1.0")
        try XCStringsFileHandler(path: path).save(file)
    }

    @Test func `tool creation`() {
        let tool = XCStringsPromoteLiteralsTool(pathUtility: PathUtility(basePath: "/workspace"))
        #expect(tool.tool().name == "xcstrings_promote_literals")
    }

    @Test func `empty literals rejected`() async throws {
        let tool = XCStringsPromoteLiteralsTool(pathUtility: PathUtility(basePath: "/workspace"))
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string("/workspace/Localizable.xcstrings"),
                "literals": .array([]),
            ])
        }
    }

    @Test func `creates manual keys and reports symbols`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try Self.makeFile(at: filePath)

        let parser = XCStringsParser(path: filePath)
        let promoted = try await parser.promoteLiterals([
            PromoteLiteralRequest(value: "Cancel"),
            PromoteLiteralRequest(value: "None Selected", comment: "Empty selection state"),
        ])

        #expect(promoted.count == 2)
        #expect(promoted[0].key == "CANCEL")
        #expect(promoted[0].symbol == "cancel")
        #expect(promoted[0].status == .created)
        #expect(promoted[1].key == "NONE_SELECTED")
        #expect(promoted[1].symbol == "noneSelected")

        // Persisted entry uses extractionState manual + source-language stringUnit + comment.
        let reloaded = try XCStringsFileHandler(path: filePath).load()
        let entry = try #require(reloaded.strings["NONE_SELECTED"])
        #expect(entry.extractionState == "manual")
        #expect(entry.comment == "Empty selection state")
        #expect(entry.localizations?["en"]?.stringUnit?.value == "None Selected")
    }

    @Test func `reuses existing key holding the same value`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try Self.makeFile(
            at: filePath,
            strings: [
                "EXISTING_CANCEL": StringEntry(
                    extractionState: "manual",
                    localizations: [
                        "en": Localization(stringUnit: StringUnit(
                            state: "translated", value: "Cancel"))
                    ],
                )
            ])

        let parser = XCStringsParser(path: filePath)
        let promoted = try await parser.promoteLiterals([PromoteLiteralRequest(value: "Cancel")])

        #expect(promoted.count == 1)
        #expect(promoted[0].status == .reused)
        #expect(promoted[0].key == "EXISTING_CANCEL")

        // No CANCEL key was created.
        let reloaded = try XCStringsFileHandler(path: filePath).load()
        #expect(reloaded.strings["CANCEL"] == nil)
    }

    @Test func `reports collision when key exists with different value`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try Self.makeFile(
            at: filePath,
            strings: [
                "CANCEL": StringEntry(
                    extractionState: "manual",
                    localizations: [
                        "en": Localization(stringUnit: StringUnit(
                            state: "translated", value: "Abort"))
                    ],
                )
            ])

        let parser = XCStringsParser(path: filePath)
        let promoted = try await parser.promoteLiterals([PromoteLiteralRequest(value: "Cancel")])

        #expect(promoted[0].status == .collision)
        #expect(promoted[0].message?.contains("Abort") == true)

        // The existing value is untouched.
        let reloaded = try XCStringsFileHandler(path: filePath).load()
        #expect(reloaded.strings["CANCEL"]?.localizations?["en"]?.stringUnit?.value == "Abort")
    }

    @Test func `explicit key overrides derived key`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try Self.makeFile(at: filePath)

        let parser = XCStringsParser(path: filePath)
        let promoted = try await parser.promoteLiterals([
            PromoteLiteralRequest(value: "Save", key: "SAVE_DOCUMENT")
        ])

        #expect(promoted[0].key == "SAVE_DOCUMENT")
        #expect(promoted[0].symbol == "saveDocument")
        #expect(promoted[0].status == .created)
    }

    @Test func `promotes parameterized value with explicit key`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try Self.makeFile(at: filePath)

        let parser = XCStringsParser(path: filePath)
        let promoted = try await parser.promoteLiterals([
            PromoteLiteralRequest(
                value: "Add %1$(ordinal)@ citation",
                key: "ADD_CITATION_TO_GROUP",
                comment: "For example, \"Add 3rd Citation\"",
            )
        ])

        #expect(promoted[0].status == .created)
        #expect(promoted[0].symbol == "addCitationToGroup")
        #expect(promoted[0].signature == "addCitationToGroup(ordinal: String)")

        // The format string is stored verbatim so Xcode parses the placeholder.
        let reloaded = try XCStringsFileHandler(path: filePath).load()
        let entry = try #require(reloaded.strings["ADD_CITATION_TO_GROUP"])
        #expect(entry.localizations?["en"]?.stringUnit?.value == "Add %1$(ordinal)@ citation")
    }

    @Test func `end to end through tool returns json`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try Self.makeFile(at: filePath)

        let tool = XCStringsPromoteLiteralsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath), "literals": .array([.object(["value": .string("Delete")])]),
        ])

        #expect(result.content.count == 1)

        if case let .text(content, _, _) = result.content[0] {
            #expect(
                content.contains("\"key\" : \"DELETE\"") || content.contains("\"key\":\"DELETE\""))
            #expect(content.contains("delete"))
            #expect(content.contains("created"))
        } else {
            Issue.record("Expected text content")
        }
    }
}
