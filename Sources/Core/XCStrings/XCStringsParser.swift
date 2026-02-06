import Foundation

/// Facade for xcstrings file operations
/// Delegates to specialized components following Single Responsibility Principle
public actor XCStringsParser {
    private let fileHandler: XCStringsFileHandler

    public init(path: String) {
        self.fileHandler = XCStringsFileHandler(path: path)
    }

    // MARK: - File Operations

    /// Load file from disk
    func load() throws -> XCStringsFile {
        try fileHandler.load()
    }

    /// Save file to disk
    func save(_ file: XCStringsFile) throws {
        try fileHandler.save(file)
    }

    /// Create a new xcstrings file
    public func createFile(sourceLanguage: String, overwrite: Bool = false) throws {
        try fileHandler.create(sourceLanguage: sourceLanguage, overwrite: overwrite)
    }

    /// Create a new xcstrings file (static version for convenience)
    public static func createFile(at path: String, sourceLanguage: String, overwrite: Bool = false)
        throws
    {
        let handler = XCStringsFileHandler(path: path)
        try handler.create(sourceLanguage: sourceLanguage, overwrite: overwrite)
    }

    // MARK: - Read Operations

    /// Get all keys sorted alphabetically
    public func listKeys() throws -> [String] {
        let file = try load()
        return XCStringsReader(file: file).listKeys()
    }

    /// Get all languages used in the file
    public func listLanguages() throws -> [String] {
        let file = try load()
        return XCStringsReader(file: file).listLanguages()
    }

    /// Get untranslated keys for a specific language
    public func listUntranslated(for language: String) throws -> [String] {
        let file = try load()
        return XCStringsReader(file: file).listUntranslated(for: language)
    }

    /// Get source language
    public func getSourceLanguage() throws -> String {
        let file = try load()
        return XCStringsReader(file: file).getSourceLanguage()
    }

    /// Get key information
    public func getKey(_ key: String) throws -> KeyInfo {
        let file = try load()
        return try XCStringsReader(file: file).getKey(key)
    }

    /// Get translation for a key
    public func getTranslation(key: String, language: String?) throws -> [String: TranslationInfo] {
        let file = try load()
        return try XCStringsReader(file: file).getTranslation(key: key, language: language)
    }

    /// Check if a key exists
    public func checkKey(_ key: String, language: String?) throws -> Bool {
        let file = try load()
        return XCStringsReader(file: file).checkKey(key, language: language)
    }

    /// Check coverage for a key
    public func checkCoverage(_ key: String) throws -> CoverageInfo {
        let file = try load()
        return try XCStringsReader(file: file).checkCoverage(key)
    }

    /// List keys with extractionState == "stale"
    public func listStaleKeys() throws -> [String] {
        let file = try load()
        return XCStringsReader(file: file).listStaleKeys()
    }

    /// Check if multiple keys exist
    public func checkKeys(_ keys: [String], language: String?) throws -> [String: Bool] {
        let file = try load()
        return XCStringsReader(file: file).checkKeys(keys, language: language)
    }

    /// List stale keys across multiple files
    public static func batchListStaleKeys(paths: [String]) throws -> BatchStaleKeysSummary {
        let results: [StaleKeysResult] = try paths.map { path in
            let handler = XCStringsFileHandler(path: path)
            let file = try handler.load()
            let staleKeys = XCStringsReader(file: file).listStaleKeys()
            return StaleKeysResult(file: path, staleKeys: staleKeys)
        }
        return BatchStaleKeysSummary(files: results)
    }

    // MARK: - Stats Operations

    /// Get overall statistics
    public func getStats() throws -> StatsInfo {
        let file = try load()
        return XCStringsStatsCalculator(file: file).getStats()
    }

    /// Get progress for a specific language
    public func getProgress(for language: String) throws -> LanguageStats {
        let file = try load()
        return try XCStringsStatsCalculator(file: file).getProgress(for: language)
    }

    /// Get batch coverage for multiple files (token-efficient)
    public static func getBatchCoverage(paths: [String]) throws -> BatchCoverageSummary {
        let files: [(path: String, file: XCStringsFile)] = try paths.map { path in
            let handler = XCStringsFileHandler(path: path)
            let file = try handler.load()
            return (path, file)
        }
        return XCStringsStatsCalculator.getBatchCoverage(files: files)
    }

    // MARK: - Compact Stats Operations (100% languages omitted)

    /// Get compact statistics (only shows incomplete languages)
    public func getCompactStats() throws -> CompactStatsInfo {
        let file = try load()
        return XCStringsStatsCalculator(file: file).getCompactStats()
    }

    /// Get compact batch coverage for multiple files
    public static func getCompactBatchCoverage(paths: [String]) throws
        -> CompactBatchCoverageSummary
    {
        let files: [(path: String, file: XCStringsFile)] = try paths.map { path in
            let handler = XCStringsFileHandler(path: path)
            let file = try handler.load()
            return (path, file)
        }
        return XCStringsStatsCalculator.getCompactBatchCoverage(files: files)
    }

    // MARK: - Write Operations

    /// Add a translation
    public func addTranslation(
        key: String, language: String, value: String, allowOverwrite: Bool = false
    ) throws {
        let file = try load()
        let updated = try XCStringsWriter.addTranslation(
            to: file, key: key, language: language, value: value, allowOverwrite: allowOverwrite)
        try save(updated)
    }

    /// Add translations for multiple languages
    public func addTranslations(
        key: String, translations: [String: String], allowOverwrite: Bool = false
    ) throws {
        let file = try load()
        let updated = try XCStringsWriter.addTranslations(
            to: file, key: key, translations: translations, allowOverwrite: allowOverwrite)
        try save(updated)
    }

    /// Update an existing translation
    public func updateTranslation(key: String, language: String, value: String) throws {
        let file = try load()
        let updated = try XCStringsWriter.updateTranslation(
            in: file, key: key, language: language, value: value)
        try save(updated)
    }

    /// Update translations for multiple languages
    public func updateTranslations(key: String, translations: [String: String]) throws {
        let file = try load()
        let updated = try XCStringsWriter.updateTranslations(
            in: file, key: key, translations: translations)
        try save(updated)
    }

    /// Rename a key
    public func renameKey(from oldKey: String, to newKey: String) throws {
        let file = try load()
        let updated = try XCStringsWriter.renameKey(in: file, from: oldKey, to: newKey)
        try save(updated)
    }

    // MARK: - Batch Write Operations

    /// Add translations for multiple keys
    public func addTranslationsBatch(
        entries: [BatchTranslationEntry], allowOverwrite: Bool = false
    ) throws -> BatchWriteResult {
        let file = try load()
        let (updated, result) = XCStringsWriter.addTranslationsBatch(
            to: file, entries: entries, allowOverwrite: allowOverwrite)
        if result.succeeded > 0 {
            try save(updated)
        }
        return result
    }

    /// Update translations for multiple keys
    public func updateTranslationsBatch(entries: [BatchTranslationEntry]) throws -> BatchWriteResult
    {
        let file = try load()
        let (updated, result) = XCStringsWriter.updateTranslationsBatch(
            in: file, entries: entries)
        if result.succeeded > 0 {
            try save(updated)
        }
        return result
    }

    // MARK: - Delete Operations

    /// Delete a key entirely
    public func deleteKey(_ key: String) throws {
        let file = try load()
        let updated = try XCStringsWriter.deleteKey(from: file, key: key)
        try save(updated)
    }

    /// Delete a translation for a specific language
    public func deleteTranslation(key: String, language: String) throws {
        let file = try load()
        let updated = try XCStringsWriter.deleteTranslation(
            from: file, key: key, language: language)
        try save(updated)
    }

    /// Delete translations for multiple languages
    public func deleteTranslations(key: String, languages: [String]) throws {
        let file = try load()
        let updated = try XCStringsWriter.deleteTranslations(
            from: file, key: key, languages: languages)
        try save(updated)
    }
}
