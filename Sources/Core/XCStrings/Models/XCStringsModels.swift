import Foundation

// MARK: - Core Data Structures

/// Root structure of xcstrings file
public struct XCStringsFile: Codable, Sendable {
    public var sourceLanguage: String
    public var strings: [String: StringEntry]
    public var version: String

    public init(
        sourceLanguage: String = "en", strings: [String: StringEntry] = [:], version: String = "1.0"
    ) {
        self.sourceLanguage = sourceLanguage
        self.strings = strings
        self.version = version
    }
}

/// String entry for each key
public struct StringEntry: Codable, Sendable {
    public var comment: String?
    public var extractionState: String?
    public var localizations: [String: Localization]?

    public init(
        comment: String? = nil,
        extractionState: String? = nil,
        localizations: [String: Localization]? = nil
    ) {
        self.comment = comment
        self.extractionState = extractionState
        self.localizations = localizations
    }
}

/// Localization entry
public struct Localization: Codable, Sendable {
    public var stringUnit: StringUnit?
    public var variations: Variations?

    public init(stringUnit: StringUnit? = nil, variations: Variations? = nil) {
        self.stringUnit = stringUnit
        self.variations = variations
    }
}

/// String unit containing the actual translation value
public struct StringUnit: Codable, Sendable {
    public var state: String
    public var value: String

    public init(state: String = "translated", value: String) {
        self.state = state
        self.value = value
    }
}

/// Variations (plural, device, etc.)
public struct Variations: Codable, Sendable {
    public var plural: PluralVariation?
    public var device: DeviceVariation?

    public init(plural: PluralVariation? = nil, device: DeviceVariation? = nil) {
        self.plural = plural
        self.device = device
    }
}

/// Plural variation
public struct PluralVariation: Codable, Sendable {
    public var zero: StringUnit?
    public var one: StringUnit?
    public var two: StringUnit?
    public var few: StringUnit?
    public var many: StringUnit?
    public var other: StringUnit?

    public init(
        zero: StringUnit? = nil,
        one: StringUnit? = nil,
        two: StringUnit? = nil,
        few: StringUnit? = nil,
        many: StringUnit? = nil,
        other: StringUnit? = nil
    ) {
        self.zero = zero
        self.one = one
        self.two = two
        self.few = few
        self.many = many
        self.other = other
    }
}

/// Device variation
public struct DeviceVariation: Codable, Sendable {
    public var iphone: StringUnit?
    public var ipad: StringUnit?
    public var mac: StringUnit?
    public var applewatch: StringUnit?
    public var appletv: StringUnit?

    public init(
        iphone: StringUnit? = nil,
        ipad: StringUnit? = nil,
        mac: StringUnit? = nil,
        applewatch: StringUnit? = nil,
        appletv: StringUnit? = nil
    ) {
        self.iphone = iphone
        self.ipad = ipad
        self.mac = mac
        self.applewatch = applewatch
        self.appletv = appletv
    }
}

// MARK: - Output Models

/// Key information for output
public struct KeyInfo: Codable, Sendable {
    public let key: String
    public let comment: String?
    public let extractionState: String?
    public let languages: [String]

    public init(key: String, comment: String?, extractionState: String?, languages: [String]) {
        self.key = key
        self.comment = comment
        self.extractionState = extractionState
        self.languages = languages
    }
}

/// Translation information for output
public struct TranslationInfo: Codable, Sendable {
    public let key: String
    public let language: String
    public let value: String?
    public let state: String?
    public let hasVariations: Bool

    public init(key: String, language: String, value: String?, state: String?, hasVariations: Bool)
    {
        self.key = key
        self.language = language
        self.value = value
        self.state = state
        self.hasVariations = hasVariations
    }
}

/// Coverage information for output
public struct CoverageInfo: Codable, Sendable {
    public let key: String
    public let translatedLanguages: [String]
    public let missingLanguages: [String]
    public let coveragePercent: Double

    public init(
        key: String,
        translatedLanguages: [String],
        missingLanguages: [String],
        coveragePercent: Double
    ) {
        self.key = key
        self.translatedLanguages = translatedLanguages
        self.missingLanguages = missingLanguages
        self.coveragePercent = coveragePercent
    }
}

/// Overall statistics for output
public struct StatsInfo: Codable, Sendable {
    public let totalKeys: Int
    public let sourceLanguage: String
    public let languages: [String]
    public let coverageByLanguage: [String: LanguageStats]

    public init(
        totalKeys: Int,
        sourceLanguage: String,
        languages: [String],
        coverageByLanguage: [String: LanguageStats]
    ) {
        self.totalKeys = totalKeys
        self.sourceLanguage = sourceLanguage
        self.languages = languages
        self.coverageByLanguage = coverageByLanguage
    }
}

/// Per-language statistics
public struct LanguageStats: Codable, Sendable {
    public let translated: Int
    public let untranslated: Int
    public let total: Int
    public let coveragePercent: Double

    public init(translated: Int, untranslated: Int, total: Int, coveragePercent: Double) {
        self.translated = translated
        self.untranslated = untranslated
        self.total = total
        self.coveragePercent = coveragePercent
    }
}

/// Token-efficient batch coverage summary for multiple files
public struct BatchCoverageSummary: Codable, Sendable {
    public let files: [FileCoverageSummary]
    public let aggregated: AggregatedCoverage

    public init(files: [FileCoverageSummary], aggregated: AggregatedCoverage) {
        self.files = files
        self.aggregated = aggregated
    }
}

/// Compact coverage summary for a single file
public struct FileCoverageSummary: Codable, Sendable {
    public let file: String
    public let totalKeys: Int
    public let languages: [String: Double]

    public init(file: String, totalKeys: Int, languages: [String: Double]) {
        self.file = file
        self.totalKeys = totalKeys
        self.languages = languages
    }
}

/// Aggregated coverage across all files
public struct AggregatedCoverage: Codable, Sendable {
    public let totalFiles: Int
    public let totalKeys: Int
    public let averageCoverageByLanguage: [String: Double]

    public init(totalFiles: Int, totalKeys: Int, averageCoverageByLanguage: [String: Double]) {
        self.totalFiles = totalFiles
        self.totalKeys = totalKeys
        self.averageCoverageByLanguage = averageCoverageByLanguage
    }
}

// MARK: - Stale Key Models

/// Result of listing stale keys in a single file
public struct StaleKeysResult: Codable, Sendable {
    public let file: String
    public let staleKeys: [String]
    public let count: Int

    public init(file: String, staleKeys: [String]) {
        self.file = file
        self.staleKeys = staleKeys
        self.count = staleKeys.count
    }
}

/// Summary of stale keys across multiple files
public struct BatchStaleKeysSummary: Codable, Sendable {
    public let files: [StaleKeysResult]
    public let totalStaleKeys: Int

    public init(files: [StaleKeysResult]) {
        self.files = files
        self.totalStaleKeys = files.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Batch Check Models

/// Result of checking multiple keys for existence
public struct BatchCheckKeysResult: Codable, Sendable {
    public let results: [String: Bool]
    public let existCount: Int
    public let missingCount: Int

    public init(results: [String: Bool]) {
        self.results = results
        self.existCount = results.values.filter(\.self).count
        self.missingCount = results.values.filter { !$0 }.count
    }
}

// MARK: - Batch Write Models

/// Entry for a batch translation operation
public struct BatchTranslationEntry: Codable, Sendable {
    public let key: String
    public let translations: [String: String]

    public init(key: String, translations: [String: String]) {
        self.key = key
        self.translations = translations
    }
}

/// Result of a batch write operation
public struct BatchWriteResult: Codable, Sendable {
    public let succeeded: Int
    public let errors: [BatchWriteError]

    public init(succeeded: Int, errors: [BatchWriteError]) {
        self.succeeded = succeeded
        self.errors = errors
    }
}

/// Individual error from a batch write operation
public struct BatchWriteError: Codable, Sendable {
    public let key: String
    public let error: String

    public init(key: String, error: String) {
        self.key = key
        self.error = error
    }
}

// MARK: - Compact Output Models (100% languages omitted)

/// Compact stats info - only shows languages under 100%
public struct CompactStatsInfo: Codable, Sendable {
    public let totalKeys: Int
    public let sourceLanguage: String
    public let totalLanguages: Int
    public let allComplete: Bool
    public let incompleteLanguages: [String: LanguageStats]?
    public let completeCount: Int

    public init(from stats: StatsInfo) {
        self.totalKeys = stats.totalKeys
        self.sourceLanguage = stats.sourceLanguage
        self.totalLanguages = stats.languages.count

        let incomplete = stats.coverageByLanguage.filter { $0.value.coveragePercent < 100 }
        self.allComplete = incomplete.isEmpty
        self.incompleteLanguages = incomplete.isEmpty ? nil : incomplete
        self.completeCount = stats.coverageByLanguage.count - incomplete.count
    }
}

/// Compact file coverage summary - only shows languages under 100%
public struct CompactFileCoverageSummary: Codable, Sendable {
    public let file: String
    public let totalKeys: Int
    public let totalLanguages: Int
    public let allComplete: Bool
    public let incompleteLanguages: [String: Double]?
    public let completeCount: Int

    public init(from summary: FileCoverageSummary) {
        self.file = summary.file
        self.totalKeys = summary.totalKeys
        self.totalLanguages = summary.languages.count

        let incomplete = summary.languages.filter { $0.value < 100 }
        self.allComplete = incomplete.isEmpty
        self.incompleteLanguages = incomplete.isEmpty ? nil : incomplete
        self.completeCount = summary.languages.count - incomplete.count
    }
}

/// Compact batch coverage summary
public struct CompactBatchCoverageSummary: Codable, Sendable {
    public let files: [CompactFileCoverageSummary]
    public let aggregated: CompactAggregatedCoverage

    public init(from batch: BatchCoverageSummary) {
        self.files = batch.files.map { CompactFileCoverageSummary(from: $0) }
        self.aggregated = CompactAggregatedCoverage(from: batch.aggregated)
    }
}

/// Compact aggregated coverage
public struct CompactAggregatedCoverage: Codable, Sendable {
    public let totalFiles: Int
    public let totalKeys: Int
    public let totalLanguages: Int
    public let allComplete: Bool
    public let incompleteLanguages: [String: Double]?
    public let completeCount: Int

    public init(from agg: AggregatedCoverage) {
        self.totalFiles = agg.totalFiles
        self.totalKeys = agg.totalKeys
        self.totalLanguages = agg.averageCoverageByLanguage.count

        let incomplete = agg.averageCoverageByLanguage.filter { $0.value < 100 }
        self.allComplete = incomplete.isEmpty
        self.incompleteLanguages = incomplete.isEmpty ? nil : incomplete
        self.completeCount = agg.averageCoverageByLanguage.count - incomplete.count
    }
}
