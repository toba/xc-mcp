import Foundation

/// Facade for xcstrings file operations Delegates to specialized components following Single
/// Responsibility Principle
public actor XCStringsParser {
    private let fileHandler: XCStringsFileHandler

    public init(path: String) { fileHandler = XCStringsFileHandler(path: path) }

    // MARK: - File Operations

    /// Load file from disk
    func load() throws(XCStringsError) -> XCStringsFile { try fileHandler.load() }

    /// Save file to disk
    func save(_ file: XCStringsFile) throws(XCStringsError) { try fileHandler.save(file) }

    /// Create a new xcstrings file
    public func createFile(sourceLanguage: String, overwrite: Bool = false) throws(XCStringsError) {
        try fileHandler.create(sourceLanguage: sourceLanguage, overwrite: overwrite)
    }

    /// Create a new xcstrings file (static version for convenience)
    public static func createFile(
        at path: String,
        sourceLanguage: String,
        overwrite: Bool = false
    )
        throws(XCStringsError)
    {
        let handler = XCStringsFileHandler(path: path)
        try handler.create(sourceLanguage: sourceLanguage, overwrite: overwrite)
    }

    // MARK: - Read Operations

    private func withReader<T>(
        _ operation: (XCStringsReader) throws(XCStringsError) -> T
    )
        throws(XCStringsError) -> T
    {
        let file = try load()
        return try operation(XCStringsReader(file: file))
    }

    private func withStats<T>(
        _ operation: (XCStringsStatsCalculator) throws(XCStringsError) -> T
    )
        throws(XCStringsError) -> T
    {
        let file = try load()
        return try operation(XCStringsStatsCalculator(file: file))
    }

    /// Load every catalog at `paths`, in order.
    private static func loadFiles(
        paths: [String]
    ) throws(XCStringsError) -> [(path: String, file: XCStringsFile)] {
        var files: [(path: String, file: XCStringsFile)] = []
        files.reserveCapacity(paths.count)
        for path in paths { files.append((path, try XCStringsFileHandler(path: path).load())) }
        return files
    }

    /// Get all keys sorted alphabetically
    public func listKeys() throws(XCStringsError) -> [String] { try withReader { $0.listKeys() } }

    /// Get all languages used in the file
    public func listLanguages() throws(XCStringsError) -> [String] {
        try withReader { $0.listLanguages() }
    }

    /// Get untranslated keys for a specific language
    public func listUntranslated(for language: String) throws(XCStringsError) -> [String] {
        try withReader { $0.listUntranslated(for: language) }
    }

    /// Detect untranslated entries with structured reasons across one or more languages. Inspects
    /// state, empty values, and variation completeness.
    public func checkUntranslated(
        languages: [String]
    ) throws(XCStringsError) -> [UntranslatedIssue] {
        try withReader { $0.checkUntranslated(languages: languages) }
    }

    /// Get source language
    public func getSourceLanguage() throws(XCStringsError) -> String {
        try withReader { $0.getSourceLanguage() }
    }

    /// Get key information
    public func getKey(_ key: String) throws(XCStringsError) -> KeyInfo {
        try XCStringsReader(file: load()).getKey(key)
    }

    /// Get translation for a key
    public func getTranslation(
        key: String,
        language: String?
    ) throws(XCStringsError) -> [String:
        TranslationInfo]
    { try XCStringsReader(file: load()).getTranslation(key: key, language: language) }

    /// Check if a key exists
    public func checkKey(_ key: String, language: String?) throws(XCStringsError) -> Bool {
        try withReader { $0.checkKey(key, language: language) }
    }

    /// Find existing keys whose NFKC-normalized form matches the queried key's NFKC form. Useful
    /// for surfacing "did you mean" hints when a caller passes an APOSTROPHE U+0027 instead of the
    /// RIGHT SINGLE QUOTATION MARK U+2019 that Xcode actually wrote.
    public func suggestions(for key: String) throws(XCStringsError) -> [String] {
        try withReader { $0.suggestions(for: key) }
    }

    /// Check coverage for a key
    public func checkCoverage(_ key: String) throws(XCStringsError) -> CoverageInfo {
        try XCStringsReader(file: load()).checkCoverage(key)
    }

    /// List keys with extractionState == "stale"
    public func listStaleKeys() throws(XCStringsError) -> [String] {
        try withReader { $0.listStaleKeys() }
    }

    /// Check if multiple keys exist
    public func checkKeys(
        _ keys: [String],
        language: String?
    ) throws(XCStringsError) -> [String:
        Bool]
    { try withReader { $0.checkKeys(keys, language: language) } }

    /// List stale keys across multiple files
    public static func batchListStaleKeys(
        paths: [String]
    ) throws(XCStringsError) -> BatchStaleKeysSummary {
        let results = try loadFiles(paths: paths).map { path, file in
            StaleKeysResult(file: path, staleKeys: XCStringsReader(file: file).listStaleKeys())
        }
        return .init(files: results)
    }

    // MARK: - Stats Operations

    /// Get overall statistics
    public func getStats() throws(XCStringsError) -> StatsInfo { try withStats { $0.getStats() } }

    /// Get progress for a specific language
    public func getProgress(for language: String) throws(XCStringsError) -> LanguageStats {
        try XCStringsStatsCalculator(file: load()).getProgress(for: language)
    }

    /// Get batch coverage for multiple files (token-efficient)
    public static func getBatchCoverage(
        paths: [String]
    ) throws(XCStringsError) -> BatchCoverageSummary {
        try XCStringsStatsCalculator.getBatchCoverage(files: loadFiles(paths: paths))
    }

    // MARK: - Compact Stats Operations (100% languages omitted)

    /// Get compact statistics (only shows incomplete languages)
    public func getCompactStats() throws(XCStringsError) -> CompactStatsInfo {
        try withStats { $0.getCompactStats() }
    }

    /// Get compact batch coverage for multiple files
    public static func getCompactBatchCoverage(
        paths: [String]
    ) throws(XCStringsError) -> CompactBatchCoverageSummary {
        try XCStringsStatsCalculator.getCompactBatchCoverage(files: loadFiles(paths: paths))
    }

    // MARK: - Write Operations

    /// Add a translation
    public func addTranslation(
        key: String,
        language: String,
        value: String,
        allowOverwrite: Bool = false,
    ) throws(XCStringsError) {
        try save(XCStringsWriter.addTranslation(
            to: load(), key: key, language: language, value: value, allowOverwrite: allowOverwrite,
        ))
    }

    /// Add translations for multiple languages
    public func addTranslations(
        key: String,
        translations: [String: String],
        allowOverwrite: Bool = false,
    ) throws(XCStringsError) {
        try save(XCStringsWriter.addTranslations(
            to: load(), key: key, translations: translations, allowOverwrite: allowOverwrite,
        ))
    }

    /// Update an existing translation
    public func updateTranslation(
        key: String,
        language: String,
        value: String
    )
        throws(XCStringsError)
    {
        try save(XCStringsWriter.updateTranslation(
            in: load(), key: key, language: language, value: value,
        ))
    }

    /// Update translations for multiple languages
    public func updateTranslations(
        key: String,
        translations: [String: String]
    )
        throws(XCStringsError)
    {
        try save(XCStringsWriter.updateTranslations(
            in: load(), key: key, translations: translations))
    }

    /// Promote hand-typed localizable literals to reusable manual source-language keys.
    ///
    /// For each request a `SCREAMING_SNAKE` key is derived from the literal (unless an explicit key
    /// is supplied). A literal whose value already lives under an existing key is reused rather
    /// than duplicated; a key that already exists with a *different* value is reported as a
    /// collision and skipped. The catalog is saved only when at least one key is created.
    ///
    /// Returns one ``PromotedLiteral`` per request, in order, each carrying the Swift symbol Xcode
    /// generates for the key (e.g. key `NONE_SELECTED` → `.noneSelected`).
    public func promoteLiterals(
        _ requests: [PromoteLiteralRequest],
    ) throws(XCStringsError) -> [PromotedLiteral] {
        var file = try load()
        let sourceLanguage = file.sourceLanguage

        // Map existing source-language values to their keys, for reuse.
        var valueToKey: [String: String] = [:]
        valueToKey.reserveCapacity(file.strings.count)

        for (key, entry) in file.strings {
            if let value = entry.localizations?[sourceLanguage]?.stringUnit?.value {
                valueToKey[value] = key
            }
        }

        var promoted: [PromotedLiteral] = []
        promoted.reserveCapacity(requests.count)
        var didCreate = false

        for request in requests {
            let key = request.key ?? LocalizableKeyNaming.screamingSnakeKey(from: request.value)

            // Reuse an existing key holding this exact value when no explicit key was requested.
            if request.key == nil, let existing = valueToKey[request.value] {
                promoted.append(PromotedLiteral(
                    value: request.value, key: existing, status: .reused,
                    message: "Value already present under key '\(existing)'.",
                ))
                continue
            }

            if let entry = file.strings[key] {
                let existingValue = entry.localizations?[sourceLanguage]?.stringUnit?.value

                if existingValue == request.value {
                    promoted.append(PromotedLiteral(
                        value: request.value, key: key, status: .reused,
                        message: "Key already exists with this value.",
                    ))
                } else {
                    promoted.append(PromotedLiteral(
                        value: request.value,
                        key: key,
                        status: .collision,
                        message: "Key '\(key)' already exists with a different value"
                            + (existingValue.map { " ('\($0)')" } ?? "")
                            + ". Pass an explicit key to override.",
                    ))
                }
                continue
            }

            file = try XCStringsWriter.addManualKey(
                to: file,
                key: key,
                sourceLanguage: sourceLanguage,
                value: request.value,
                comment: request.comment,
            )
            valueToKey[request.value] = key
            didCreate = true
            promoted.append(PromotedLiteral(value: request.value, key: key, status: .created))
        }

        if didCreate { try save(file) }
        return promoted
    }

    /// Rename a key
    public func renameKey(from oldKey: String, to newKey: String) throws(XCStringsError) {
        try save(XCStringsWriter.renameKey(in: load(), from: oldKey, to: newKey))
    }

    // MARK: - Batch Write Operations

    /// Add translations for multiple keys
    public func addTranslationsBatch(
        entries: [BatchTranslationEntry],
        allowOverwrite: Bool = false,
    ) throws(XCStringsError) -> BatchWriteResult {
        let file = try load()
        let (updated, result) = XCStringsWriter.addTranslationsBatch(
            to: file, entries: entries, allowOverwrite: allowOverwrite,
        )
        if result.succeeded > 0 { try save(updated) }
        return result
    }

    /// Update translations for multiple keys
    public func updateTranslationsBatch(
        entries: [BatchTranslationEntry]
    ) throws(XCStringsError) -> BatchWriteResult {
        let file = try load()
        let (updated, result) = XCStringsWriter.updateTranslationsBatch(in: file, entries: entries)
        if result.succeeded > 0 { try save(updated) }
        return result
    }

    // MARK: - Delete Operations

    /// Delete a key entirely
    public func deleteKey(_ key: String) throws(XCStringsError) {
        try save(XCStringsWriter.deleteKey(from: load(), key: key))
    }

    /// Delete a translation for a specific language
    public func deleteTranslation(key: String, language: String) throws(XCStringsError) {
        try save(XCStringsWriter.deleteTranslation(from: load(), key: key, language: language))
    }

    /// Delete translations for multiple languages
    public func deleteTranslations(key: String, languages: [String]) throws(XCStringsError) {
        try save(XCStringsWriter.deleteTranslations(from: load(), key: key, languages: languages))
    }
}
