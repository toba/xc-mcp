import Foundation
import MCP
import Testing
import XCMCPCore

@testable import XCMCPTools

// MARK: - Test Helpers

enum XCStringsTestHelper {
    /// Create a sample xcstrings file with stale keys for testing
    static func createSampleWithStaleKeys(at path: String) throws {
        let file = XCStringsFile(
            sourceLanguage: "en",
            strings: [
                "active_key": StringEntry(
                    extractionState: "manual",
                    localizations: [
                        "en": Localization(
                            stringUnit: StringUnit(state: "translated", value: "Active"))
                    ]),
                "stale_key_1": StringEntry(
                    extractionState: "stale",
                    localizations: [
                        "en": Localization(
                            stringUnit: StringUnit(state: "translated", value: "Stale 1"))
                    ]),
                "stale_key_2": StringEntry(
                    extractionState: "stale",
                    localizations: [
                        "en": Localization(
                            stringUnit: StringUnit(state: "translated", value: "Stale 2"))
                    ]),
            ],
            version: "1.0")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Create a sample xcstrings file with test data
    static func createSampleXCStringsFile(at path: String, sourceLanguage: String = "en") throws {
        let file = XCStringsFile(
            sourceLanguage: sourceLanguage,
            strings: [
                "hello": StringEntry(
                    comment: "Greeting message",
                    extractionState: "manual",
                    localizations: [
                        "en": Localization(
                            stringUnit: StringUnit(state: "translated", value: "Hello")),
                        "ja": Localization(
                            stringUnit: StringUnit(state: "translated", value: "こんにちは")),
                        "fr": Localization(
                            stringUnit: StringUnit(state: "translated", value: "Bonjour")),
                    ]),
                "goodbye": StringEntry(
                    comment: "Farewell message",
                    extractionState: "manual",
                    localizations: [
                        "en": Localization(
                            stringUnit: StringUnit(state: "translated", value: "Goodbye")),
                        "ja": Localization(
                            stringUnit: StringUnit(state: "translated", value: "さようなら")),
                    ]),
                "untranslated_key": StringEntry(
                    comment: "Key without French translation",
                    extractionState: "manual",
                    localizations: [
                        "en": Localization(
                            stringUnit: StringUnit(state: "translated", value: "Untranslated"))
                    ]),
            ],
            version: "1.0")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Create an empty xcstrings file
    static func createEmptyXCStringsFile(at path: String, sourceLanguage: String = "en") throws {
        let file = XCStringsFile(sourceLanguage: sourceLanguage, strings: [:], version: "1.0")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - XCStringsListKeysTool Tests

struct XCStringsListKeysToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsListKeysTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_list_keys")
        #expect(toolDefinition.description == "List all keys in the xcstrings file")
    }

    @Test func testMissingFileParameter() async throws {
        let tool = XCStringsListKeysTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test func testFileNotFound() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = XCStringsListKeysTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["file": .string("nonexistent.xcstrings")])
        }
    }

    @Test func testListKeys() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsListKeysTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: ["file": .string(filePath)])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("hello"))
            #expect(content.contains("goodbye"))
            #expect(content.contains("untranslated_key"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsListLanguagesTool Tests

struct XCStringsListLanguagesToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsListLanguagesTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_list_languages")
        #expect(toolDefinition.description == "List all languages in the xcstrings file")
    }

    @Test func testMissingFileParameter() async throws {
        let tool = XCStringsListLanguagesTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test func testListLanguages() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsListLanguagesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: ["file": .string(filePath)])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("en"))
            #expect(content.contains("ja"))
            #expect(content.contains("fr"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsGetSourceLanguageTool Tests

struct XCStringsGetSourceLanguageToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsGetSourceLanguageTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_get_source_language")
        #expect(toolDefinition.description == "Get the source language of the xcstrings file")
    }

    @Test func testMissingFileParameter() async throws {
        let tool = XCStringsGetSourceLanguageTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test func testGetSourceLanguage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath, sourceLanguage: "ja")

        let tool = XCStringsGetSourceLanguageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: ["file": .string(filePath)])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content == "ja")
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsGetKeyTool Tests

struct XCStringsGetKeyToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsGetKeyTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_get_key")
        #expect(toolDefinition.description == "Get translations for a specific key")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsGetKeyTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["file": .string("test.xcstrings")])
        }
    }

    @Test func testGetKeyAllLanguages() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsGetKeyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Hello"))
            #expect(content.contains("こんにちは"))
            #expect(content.contains("Bonjour"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testGetKeySpecificLanguage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsGetKeyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
            "language": .string("ja"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("こんにちは"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testGetKeyNotFound() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsGetKeyTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("nonexistent_key"),
            ])
        }
    }
}

// MARK: - XCStringsCheckKeyTool Tests

struct XCStringsCheckKeyToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsCheckKeyTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_check_key")
        #expect(toolDefinition.description == "Check if a key exists in the xcstrings file")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsCheckKeyTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["file": .string("test.xcstrings")])
        }
    }

    @Test func testCheckKeyExists() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsCheckKeyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content == "true")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testCheckKeyNotExists() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsCheckKeyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("nonexistent_key"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content == "false")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testCheckKeyWithLanguage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsCheckKeyTool(pathUtility: PathUtility(basePath: tempDir.path))

        // Check key with existing language
        let resultExists = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
            "language": .string("ja"),
        ])
        if case let .text(content) = resultExists.content[0] {
            #expect(content == "true")
        }

        // Check key with missing language
        let resultMissing = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("untranslated_key"),
            "language": .string("fr"),
        ])
        if case let .text(content) = resultMissing.content[0] {
            #expect(content == "false")
        }
    }
}

// MARK: - XCStringsListUntranslatedTool Tests

struct XCStringsListUntranslatedToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsListUntranslatedTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_list_untranslated")
        #expect(toolDefinition.description == "List untranslated keys for a specific language")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsListUntranslatedTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["file": .string("test.xcstrings")])
        }
    }

    @Test func testListUntranslated() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsListUntranslatedTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "language": .string("fr"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            // "goodbye" and "untranslated_key" don't have French translations
            #expect(content.contains("goodbye") || content.contains("untranslated_key"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsStatsCoverageTool Tests

struct XCStringsStatsCoverageToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsStatsCoverageTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_stats_coverage")
        #expect(
            toolDefinition.description
                == "Get overall translation statistics. Use compact mode to only show languages under 100%."
        )
    }

    @Test func testMissingFileParameter() async throws {
        let tool = XCStringsStatsCoverageTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test func testStatsCoverage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsStatsCoverageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "compact": .bool(false),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("totalKeys"))
            #expect(content.contains("sourceLanguage"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testStatsCoverageCompact() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsStatsCoverageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: ["file": .string(filePath)])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("totalKeys"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsStatsProgressTool Tests

struct XCStringsStatsProgressToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsStatsProgressTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_stats_progress")
        #expect(toolDefinition.description == "Get translation progress for a specific language")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsStatsProgressTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["file": .string("test.xcstrings")])
        }
    }

    @Test func testStatsProgress() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsStatsProgressTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "language": .string("ja"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("translated") || content.contains("coveragePercent"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsBatchStatsCoverageTool Tests

struct XCStringsBatchStatsCoverageToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsBatchStatsCoverageTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_batch_stats_coverage")
        #expect(toolDefinition.description?.contains("token-efficient") == true)
    }

    @Test func testEmptyFilesArray() throws {
        let tool = XCStringsBatchStatsCoverageTool(pathUtility: PathUtility(basePath: "/workspace"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["files": .array([])])
        }
    }

    @Test func testBatchStatsCoverage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath1 = tempDir.path + "/Localizable1.xcstrings"
        let filePath2 = tempDir.path + "/Localizable2.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath1)
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath2)

        let tool = XCStringsBatchStatsCoverageTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "files": .array([.string(filePath1), .string(filePath2)]),
            "compact": .bool(false),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("files"))
            #expect(content.contains("aggregated"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsCreateFileTool Tests

struct XCStringsCreateFileToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsCreateFileTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_create_file")
        #expect(
            toolDefinition.description
                == "Create a new xcstrings file with the specified source language")
    }

    @Test func testMissingFileParameter() throws {
        let tool = XCStringsCreateFileTool(pathUtility: PathUtility(basePath: "/workspace"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
    }

    @Test func testCreateFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/NewLocalizable.xcstrings"
        let tool = XCStringsCreateFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "file": .string(filePath),
            "sourceLanguage": .string("ja"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Created xcstrings file"))
            #expect(content.contains("ja"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: filePath))
    }

    @Test func testCreateFileAlreadyExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsCreateFileTool(pathUtility: PathUtility(basePath: tempDir.path))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["file": .string(filePath)])
        }
    }

    @Test func testCreateFileWithOverwrite() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsCreateFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "file": .string(filePath),
            "overwrite": .bool(true),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Created xcstrings file"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsAddTranslationTool Tests

struct XCStringsAddTranslationToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsAddTranslationTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_add_translation")
        #expect(toolDefinition.description == "Add a translation for a key")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsAddTranslationTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string("test.xcstrings"),
                "key": .string("test_key"),
            ])
        }
    }

    @Test func testAddTranslation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsAddTranslationTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("new_key"),
            "language": .string("de"),
            "value": .string("Hallo"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Translation added successfully"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsAddTranslationsTool Tests

struct XCStringsAddTranslationsToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsAddTranslationsTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_add_translations")
        #expect(toolDefinition.description == "Add translations for multiple languages at once")
    }

    @Test func testMissingTranslations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsAddTranslationsTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("test_key"),
            ])
        }
    }

    @Test func testAddTranslations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsAddTranslationsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("new_key"),
            "translations": .object([
                "de": .string("Hallo"),
                "es": .string("Hola"),
            ]),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Translations added successfully"))
            #expect(content.contains("2 languages"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsUpdateTranslationTool Tests

struct XCStringsUpdateTranslationToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsUpdateTranslationTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_update_translation")
        #expect(toolDefinition.description == "Update a translation for a key")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsUpdateTranslationTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test func testUpdateTranslation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsUpdateTranslationTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
            "language": .string("en"),
            "value": .string("Hi there!"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Translation updated successfully"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testUpdateNonexistentKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsUpdateTranslationTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("nonexistent_key"),
                "language": .string("en"),
                "value": .string("Test"),
            ])
        }
    }
}

// MARK: - XCStringsUpdateTranslationsTool Tests

struct XCStringsUpdateTranslationsToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsUpdateTranslationsTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_update_translations")
        #expect(toolDefinition.description == "Update translations for multiple languages at once")
    }

    @Test func testEmptyTranslations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsUpdateTranslationsTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("hello"),
                "translations": .object([:]),
            ])
        }
    }

    @Test func testUpdateTranslations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsUpdateTranslationsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
            "translations": .object([
                "en": .string("Hi!"),
                "ja": .string("やあ！"),
            ]),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Translations updated successfully"))
            #expect(content.contains("2 languages"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsRenameKeyTool Tests

struct XCStringsRenameKeyToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsRenameKeyTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_rename_key")
        #expect(toolDefinition.description == "Rename a key")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsRenameKeyTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string("test.xcstrings"),
                "oldKey": .string("old"),
            ])
        }
    }

    @Test func testRenameKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsRenameKeyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "oldKey": .string("hello"),
            "newKey": .string("greeting"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Key renamed"))
            #expect(content.contains("hello"))
            #expect(content.contains("greeting"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testRenameNonexistentKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsRenameKeyTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "oldKey": .string("nonexistent"),
                "newKey": .string("new_name"),
            ])
        }
    }
}

// MARK: - XCStringsDeleteKeyTool Tests

struct XCStringsDeleteKeyToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsDeleteKeyTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_delete_key")
        #expect(toolDefinition.description == "Delete a key entirely")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsDeleteKeyTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["file": .string("test.xcstrings")])
        }
    }

    @Test func testDeleteKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsDeleteKeyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Key deleted successfully"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testDeleteNonexistentKey() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsDeleteKeyTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("nonexistent_key"),
            ])
        }
    }
}

// MARK: - XCStringsDeleteTranslationTool Tests

struct XCStringsDeleteTranslationToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsDeleteTranslationTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_delete_translation")
        #expect(toolDefinition.description == "Delete a specific translation for a key")
    }

    @Test func testMissingParameters() async throws {
        let tool = XCStringsDeleteTranslationTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string("test.xcstrings"),
                "key": .string("hello"),
            ])
        }
    }

    @Test func testDeleteTranslation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsDeleteTranslationTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
            "language": .string("fr"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Translation for 'fr' deleted successfully"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testDeleteNonexistentTranslation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsDeleteTranslationTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("hello"),
                "language": .string("zh"),
            ])
        }
    }
}

// MARK: - XCStringsDeleteTranslationsTool Tests

struct XCStringsDeleteTranslationsToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsDeleteTranslationsTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_delete_translations")
        #expect(toolDefinition.description == "Delete translations for multiple languages at once")
    }

    @Test func testEmptyLanguagesArray() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsDeleteTranslationsTool(pathUtility: PathUtility(basePath: tempDir.path))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("hello"),
                "languages": .array([]),
            ])
        }
    }

    @Test func testDeleteTranslations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.path + "/Localizable.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsDeleteTranslationsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
            "languages": .array([.string("ja"), .string("fr")]),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Translations deleted successfully"))
            #expect(content.contains("2 languages"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsListStaleTool Tests

struct XCStringsListStaleToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsListStaleTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_list_stale")
        #expect(toolDefinition.description?.contains("stale") == true)
    }

    @Test func testListStaleKeys() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsListStaleTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createSampleWithStaleKeys(at: filePath)

        let tool = XCStringsListStaleTool(pathUtility: PathUtility(basePath: tempDir))
        let result = try await tool.execute(arguments: ["file": .string(filePath)])

        if case let .text(json) = result.content[0] {
            #expect(json.contains("stale_key_1"))
            #expect(json.contains("stale_key_2"))
            #expect(!json.contains("active_key") || json.contains("\"count\" : 2"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testNoStaleKeys() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsListStaleTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsListStaleTool(pathUtility: PathUtility(basePath: tempDir))
        let result = try await tool.execute(arguments: ["file": .string(filePath)])

        if case let .text(json) = result.content[0] {
            #expect(json.contains("\"count\" : 0"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsBatchListStaleTool Tests

struct XCStringsBatchListStaleToolTests {
    @Test func testBatchListStale() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsBatchListStaleTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let file1 = "\(tempDir)/test1.xcstrings"
        let file2 = "\(tempDir)/test2.xcstrings"
        try XCStringsTestHelper.createSampleWithStaleKeys(at: file1)
        try XCStringsTestHelper.createSampleXCStringsFile(at: file2)

        let tool = XCStringsBatchListStaleTool(pathUtility: PathUtility(basePath: tempDir))
        let result = try tool.execute(arguments: [
            "files": .array([.string(file1), .string(file2)])
        ])

        if case let .text(json) = result.content[0] {
            #expect(json.contains("totalStaleKeys"))
            #expect(json.contains("stale_key_1"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testEmptyFilesArray() throws {
        let tool = XCStringsBatchListStaleTool(pathUtility: PathUtility(basePath: "/workspace"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["files": .array([])])
        }
    }
}

// MARK: - XCStringsBatchCheckKeysTool Tests

struct XCStringsBatchCheckKeysToolTests {
    @Test func testBatchCheckKeys() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsBatchCheckKeysTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsBatchCheckKeysTool(pathUtility: PathUtility(basePath: tempDir))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "keys": .array([.string("hello"), .string("nonexistent"), .string("goodbye")]),
        ])

        if case let .text(json) = result.content[0] {
            #expect(json.contains("\"existCount\" : 2"))
            #expect(json.contains("\"missingCount\" : 1"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testBatchCheckKeysWithLanguage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsBatchCheckKeysTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsBatchCheckKeysTool(pathUtility: PathUtility(basePath: tempDir))
        // "goodbye" has no "fr" translation, "hello" does
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "keys": .array([.string("hello"), .string("goodbye")]),
            "language": .string("fr"),
        ])

        if case let .text(json) = result.content[0] {
            #expect(json.contains("\"existCount\" : 1"))
            #expect(json.contains("\"missingCount\" : 1"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testEmptyKeysArray() async throws {
        let tool = XCStringsBatchCheckKeysTool(pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string("/dummy.xcstrings"),
                "keys": .array([]),
            ])
        }
    }
}

// MARK: - XCStringsBatchAddTranslationsTool Tests

struct XCStringsBatchAddTranslationsToolTests {
    @Test func testBatchAddTranslations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsBatchAddTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createEmptyXCStringsFile(at: filePath)

        let tool = XCStringsBatchAddTranslationsTool(pathUtility: PathUtility(basePath: tempDir))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "entries": .array([
                .object([
                    "key": .string("greeting"),
                    "translations": .object([
                        "en": .string("Hello"),
                        "fr": .string("Bonjour"),
                    ]),
                ]),
                .object([
                    "key": .string("farewell"),
                    "translations": .object([
                        "en": .string("Bye")
                    ]),
                ]),
            ]),
        ])

        if case let .text(json) = result.content[0] {
            #expect(json.contains("\"succeeded\" : 2"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testEmptyEntries() async throws {
        let tool = XCStringsBatchAddTranslationsTool(
            pathUtility: PathUtility(basePath: "/workspace"))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string("/dummy.xcstrings"),
                "entries": .array([]),
            ])
        }
    }
}

// MARK: - XCStringsBatchUpdateTranslationsTool Tests

struct XCStringsBatchUpdateTranslationsToolTests {
    @Test func testBatchUpdateTranslations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsBatchUpdateTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsBatchUpdateTranslationsTool(
            pathUtility: PathUtility(basePath: tempDir))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "entries": .array([
                .object([
                    "key": .string("hello"),
                    "translations": .object([
                        "en": .string("Hi there")
                    ]),
                ]),
                .object([
                    "key": .string("nonexistent"),
                    "translations": .object([
                        "en": .string("Nope")
                    ]),
                ]),
            ]),
        ])

        if case let .text(json) = result.content[0] {
            // First key succeeds, second fails
            #expect(json.contains("\"succeeded\" : 1"))
            #expect(json.contains("\"errors\""))
            #expect(json.contains("nonexistent"))
        } else {
            Issue.record("Expected text content")
        }
    }
}

// MARK: - XCStringsCheckCoverageTool Tests

struct XCStringsCheckCoverageToolTests {
    @Test func testToolCreation() {
        let tool = XCStringsCheckCoverageTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "xcstrings_check_coverage")
        #expect(toolDefinition.description?.contains("coverage") == true)
    }

    @Test func testCheckCoverage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsCheckCoverageTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsCheckCoverageTool(pathUtility: PathUtility(basePath: tempDir))
        let result = try await tool.execute(arguments: [
            "file": .string(filePath),
            "key": .string("hello"),
        ])

        if case let .text(json) = result.content[0] {
            #expect(json.contains("coveragePercent"))
            #expect(json.contains("translatedLanguages"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testCheckCoverageKeyNotFound() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "XCStringsCheckCoverageTests-\(UUID().uuidString)"
        ).path
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filePath = "\(tempDir)/test.xcstrings"
        try XCStringsTestHelper.createSampleXCStringsFile(at: filePath)

        let tool = XCStringsCheckCoverageTool(pathUtility: PathUtility(basePath: tempDir))

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "file": .string(filePath),
                "key": .string("nonexistent_key"),
            ])
        }
    }
}
