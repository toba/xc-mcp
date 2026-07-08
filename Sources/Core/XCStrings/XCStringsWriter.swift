import Foundation

/// Handles write operations for xcstrings files
public enum XCStringsWriter {
    /// A localization holding a single `translated`-state string value.
    private static func translated(_ value: String) -> Localization {
        .init(stringUnit: StringUnit(state: "translated", value: value))
    }

    /// Add a translation for a key
    public static func addTranslation(
        to file: XCStringsFile,
        key: String,
        language: String,
        value: String,
        allowOverwrite: Bool = false,
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        if result.strings[key] == nil { result.strings[key] = StringEntry(localizations: [:]) }

        if !allowOverwrite, result.strings[key]?.localizations?[language] != nil {
            throw XCStringsError.keyAlreadyExists(key: "\(key):\(language)")
        }

        if result.strings[key]?.localizations == nil { result.strings[key]?.localizations = [:] }

        result.strings[key]?.localizations?[language] = translated(value)

        return result
    }

    /// Add translations for multiple languages
    public static func addTranslations(
        to file: XCStringsFile,
        key: String,
        translations: [String: String],
        allowOverwrite: Bool = false,
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        if result.strings[key] == nil { result.strings[key] = StringEntry(localizations: [:]) }

        if result.strings[key]?.localizations == nil { result.strings[key]?.localizations = [:] }

        for (language, value) in translations {
            if !allowOverwrite, result.strings[key]?.localizations?[language] != nil {
                throw XCStringsError.keyAlreadyExists(key: "\(key):\(language)")
            }

            result.strings[key]?.localizations?[language] = translated(value)
        }

        return result
    }

    /// Add a manual source-language key for a promoted localizable literal.
    ///
    /// Creates an entry with `extractionState: "manual"` and a single source-language `stringUnit`
    /// holding the literal text — mirroring what Xcode writes when a key is added by hand. Throws
    /// ``XCStringsError/keyAlreadyExists(key:)`` if the key already exists (callers that want to
    /// reuse an existing key should check first).
    public static func addManualKey(
        to file: XCStringsFile,
        key: String,
        sourceLanguage: String,
        value: String,
        comment: String? = nil,
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        guard result.strings[key] == nil else { throw XCStringsError.keyAlreadyExists(key: key) }

        result.strings[key] = StringEntry(
            comment: comment,
            extractionState: "manual",
            localizations: [sourceLanguage: translated(value)],
        )

        return result
    }

    /// Update an existing translation
    public static func updateTranslation(
        in file: XCStringsFile,
        key: String,
        language: String,
        value: String,
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        guard result.strings[key] != nil else { throw XCStringsError.keyNotFound(key: key) }

        guard result.strings[key]?.localizations?[language] != nil else {
            throw XCStringsError.languageNotFound(language: language, key: key)
        }

        result.strings[key]?.localizations?[language] = translated(value)

        return result
    }

    /// Update translations for multiple languages
    public static func updateTranslations(
        in file: XCStringsFile,
        key: String,
        translations: [String: String],
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        guard result.strings[key] != nil else { throw XCStringsError.keyNotFound(key: key) }

        for (language, value) in translations {
            guard result.strings[key]?.localizations?[language] != nil else {
                throw XCStringsError.languageNotFound(language: language, key: key)
            }

            result.strings[key]?.localizations?[language] = translated(value)
        }

        return result
    }

    /// Add translations for multiple keys atomically
    public static func addTranslationsBatch(
        to file: XCStringsFile,
        entries: [BatchTranslationEntry],
        allowOverwrite: Bool = false,
    ) -> (file: XCStringsFile, result: BatchWriteResult) {
        var result = file
        var succeeded = 0
        var errors: [BatchWriteError] = []
        errors.reserveCapacity(entries.count)

        for entry in entries {
            do {
                result = try addTranslations(
                    to: result, key: entry.key, translations: entry.translations,
                    allowOverwrite: allowOverwrite,
                )
                succeeded += 1
            } catch {
                errors.append(BatchWriteError(key: entry.key, error: error.localizedDescription))
            }
        }

        return (result, BatchWriteResult(succeeded: succeeded, errors: errors))
    }

    /// Update translations for multiple keys atomically
    public static func updateTranslationsBatch(
        in file: XCStringsFile,
        entries: [BatchTranslationEntry],
    ) -> (file: XCStringsFile, result: BatchWriteResult) {
        var result = file
        var succeeded = 0
        var errors: [BatchWriteError] = []
        errors.reserveCapacity(entries.count)

        for entry in entries {
            do {
                result = try updateTranslations(
                    in: result, key: entry.key, translations: entry.translations,
                )
                succeeded += 1
            } catch {
                errors.append(BatchWriteError(key: entry.key, error: error.localizedDescription))
            }
        }

        return (result, BatchWriteResult(succeeded: succeeded, errors: errors))
    }

    /// Rename a key
    public static func renameKey(
        in file: XCStringsFile,
        from oldKey: String,
        to newKey: String,
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        guard let entry = result.strings[oldKey] else {
            throw XCStringsError.keyNotFound(key: oldKey)
        }

        if result.strings[newKey] != nil { throw XCStringsError.keyAlreadyExists(key: newKey) }

        result.strings[newKey] = entry
        result.strings.removeValue(forKey: oldKey)

        return result
    }

    /// Delete a key entirely
    public static func deleteKey(
        from file: XCStringsFile,
        key: String,
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        guard result.strings[key] != nil else { throw XCStringsError.keyNotFound(key: key) }

        result.strings.removeValue(forKey: key)

        return result
    }

    /// Delete a translation for a specific language
    public static func deleteTranslation(
        from file: XCStringsFile,
        key: String,
        language: String,
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        guard result.strings[key] != nil else { throw XCStringsError.keyNotFound(key: key) }

        guard result.strings[key]?.localizations?[language] != nil else {
            throw XCStringsError.languageNotFound(language: language, key: key)
        }

        result.strings[key]?.localizations?.removeValue(forKey: language)

        return result
    }

    /// Delete translations for multiple languages
    public static func deleteTranslations(
        from file: XCStringsFile,
        key: String,
        languages: [String],
    ) throws(XCStringsError) -> XCStringsFile {
        var result = file

        guard result.strings[key] != nil else { throw XCStringsError.keyNotFound(key: key) }

        for language in languages {
            guard result.strings[key]?.localizations?[language] != nil else {
                throw XCStringsError.languageNotFound(language: language, key: key)
            }

            result.strings[key]?.localizations?.removeValue(forKey: language)
        }

        return result
    }
}
