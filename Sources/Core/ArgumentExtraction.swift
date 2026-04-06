import MCP

/// Holds extracted test selection and coverage parameters.
public struct TestParameters: Sendable {
    public let onlyTesting: [String]?
    public let skipTesting: [String]?
    public let enableCodeCoverage: Bool
    public let resultBundlePath: String?
    public let testPlan: String?
    public let timeout: Int?
    public let outputTimeout: Int?

    public init(
        onlyTesting: [String]?,
        skipTesting: [String]?,
        enableCodeCoverage: Bool,
        resultBundlePath: String?,
        testPlan: String?,
        timeout: Int?,
        outputTimeout: Int?,
    ) {
        self.onlyTesting = onlyTesting
        self.skipTesting = skipTesting
        self.enableCodeCoverage = enableCodeCoverage
        self.resultBundlePath = resultBundlePath
        self.testPlan = testPlan
        self.timeout = timeout
        self.outputTimeout = outputTimeout
    }
}

/// Extension providing convenient argument extraction methods for MCP tool parameters.
///
/// These helpers reduce boilerplate when extracting typed values from argument dictionaries.
extension [String: Value] {
    /// Extracts an optional string value for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The string value if present and valid, nil otherwise.
    public func getString(_ key: String) -> String? {
        if case let .string(value) = self[key] {
            return value
        }
        return nil
    }

    /// Extracts a required string value for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The string value.
    /// - Throws: MCPError.invalidParams if the key is missing or not a string.
    public func getRequiredString(_ key: String) throws -> String {
        guard case let .string(value) = self[key] else {
            throw MCPError.invalidParams("\(key) is required")
        }
        return value
    }

    /// Extracts an optional boolean value for the given key.
    ///
    /// - Parameters:
    ///   - key: The argument key to look up.
    ///   - defaultValue: The value to return if the key is missing. Defaults to false.
    /// - Returns: The boolean value if present, or the default value.
    public func getBool(_ key: String, default defaultValue: Bool = false) -> Bool {
        if case let .bool(value) = self[key] {
            return value
        }
        return defaultValue
    }

    /// Extracts an optional integer value for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The integer value if present and valid, nil otherwise.
    public func getInt(_ key: String) -> Int? {
        switch self[key] {
            case let .int(value):
                return value
            case let .double(value) where value == value.rounded():
                return Int(value)
            default:
                return nil
        }
    }

    /// Extracts an optional double value for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The double value if present and valid, nil otherwise.
    public func getDouble(_ key: String) -> Double? {
        if case let .double(value) = self[key] {
            return value
        }
        return nil
    }

    /// Extracts a string-to-string dictionary for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: A dictionary of string key-value pairs. Returns empty dictionary if key is missing or not an object.
    public func getStringDictionary(_ key: String) -> [String: String] {
        guard case let .object(obj) = self[key] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (k, v) in obj {
            if case let .string(s) = v {
                result[k] = s
            }
        }
        return result
    }

    /// Extracts xcodebuild build setting overrides and returns them as `["KEY=VALUE", ...]`.
    ///
    /// - Parameter key: The argument key to look up. Defaults to `"build_settings"`.
    /// - Returns: An array of `KEY=VALUE` strings suitable for xcodebuild positional arguments.
    public func buildSettingOverrides(_ key: String = "build_settings") -> [String] {
        getStringDictionary(key).map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// Extracts a string array for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: An array of strings. Returns empty array if key is missing or not an array.
    public func getStringArray(_ key: String) -> [String] {
        guard case let .array(array) = self[key] else {
            return []
        }
        return array.compactMap { value in
            if case let .string(s) = value {
                return s
            }
            return nil
        }
    }

    /// Extracts test selection and coverage parameters from arguments.
    ///
    /// Normalizes test identifiers that use Swift Testing backtick-escaped names.
    /// If a method component contains spaces but is missing backticks and trailing `()`,
    /// they are added automatically so xcodebuild can match them.
    public func testParameters() -> TestParameters {
        let onlyTestingArray = getStringArray("only_testing").map(Self.normalizeTestIdentifier)
        let skipTestingArray = getStringArray("skip_testing").map(Self.normalizeTestIdentifier)
        return TestParameters(
            onlyTesting: onlyTestingArray.isEmpty ? nil : onlyTestingArray,
            skipTesting: skipTestingArray.isEmpty ? nil : skipTestingArray,
            enableCodeCoverage: getBool("enable_code_coverage"),
            resultBundlePath: getString("result_bundle_path"),
            testPlan: getString("test_plan"),
            timeout: getInt("timeout"),
            outputTimeout: getInt("output_timeout"),
        )
    }

    /// Normalizes a test identifier for xcodebuild's `-only-testing:` / `-skip-testing:` flags.
    ///
    /// xcodebuild expects Swift Testing backtick-escaped function names in the format:
    /// ``TargetName/TestClass/`function name with spaces`()``
    ///
    /// LLMs often pass the display name without backticks or parentheses:
    /// `"TargetName/TestClass/function name with spaces"`
    ///
    /// This also handles single-word Swift keywords used as test names (e.g. `class`, `import`)
    /// which need backtick wrapping even though they contain no spaces.
    private static func normalizeTestIdentifier(_ identifier: String) -> String {
        // Split into components: Target/Class/Method
        let parts = identifier.split(separator: "/", maxSplits: 2)
        guard parts.count == 3 else { return identifier }

        let method = parts[2]

        // Already backtick-wrapped — ensure () suffix
        if method.hasPrefix("`") {
            if method.hasSuffix("()") { return identifier }
            return "\(parts[0])/\(parts[1])/\(method)()"
        }

        let needsBackticks = method.contains(" ") || swiftKeywords.contains(String(method))

        guard needsBackticks else { return identifier }

        // Wrap in backticks and add () if missing
        var normalized = "`\(method)`"
        if !method.hasSuffix("()") {
            normalized += "()"
        }
        return "\(parts[0])/\(parts[1])/\(normalized)"
    }

    /// Swift reserved words that require backtick escaping when used as test function names.
    private static let swiftKeywords: Set<String> = [
        // Declarations
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
        "import", "init", "inout", "internal", "let", "open", "operator", "private",
        "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var",
        // Statements
        "break", "case", "continue", "default", "defer", "do", "else", "fallthrough", "for",
        "guard", "if", "in", "repeat", "return", "switch", "where", "while",
        // Expressions and types
        "as", "Any", "catch", "false", "is", "nil", "super", "self", "Self", "throw",
        "throws", "true", "try",
        // Context-sensitive (commonly used)
        "async", "await", "some", "any", "consume", "consuming", "borrowing", "sending",
        "isolated", "nonisolated", "macro",
    ]

    /// Returns the `-IDEBuildingContinueBuildingAfterErrors=YES` flag if requested.
    ///
    /// xcodebuild stops on the first build error by default. When this parameter is true,
    /// the IDE flag is appended so all targets continue building and all errors are reported.
    public func continueBuildingArgs() -> [String] {
        getBool("continue_building_after_errors")
            ? ["-IDEBuildingContinueBuildingAfterErrors=YES"]
            : []
    }

    /// Schema property for the continue-building-after-errors option.
    ///
    /// Maps to Xcode's "Continue building after errors" preference
    /// (`-IDEBuildingContinueBuildingAfterErrors`).
    public static var continueBuildingSchemaProperty: [String: Value] {
        [
            "continue_building_after_errors": .object([
                "type": .string("boolean"),
                "description": .string(
                    "When true, continue building remaining targets after a build error "
                        + "instead of stopping immediately. Maps to Xcode's "
                        + "'Continue building after errors' setting. "
                        + "Defaults to false (stop on first error).",
                ),
            ]),
        ]
    }

    /// Returns build setting overrides to disable all sanitizers unless explicitly enabled.
    ///
    /// Disables Thread Sanitizer, Address Sanitizer, and Undefined Behavior Sanitizer
    /// by default. Sanitizers significantly slow compilation, so they are opt-in.
    public func enableSanitizersArgs() -> [String] {
        getBool("enable_sanitizers")
            ? []
            : [
                "ENABLE_THREAD_SANITIZER=NO",
                "ENABLE_ADDRESS_SANITIZER=NO",
                "ENABLE_UNDEFINED_BEHAVIOR_SANITIZER=NO",
            ]
    }

    /// Schema property for the enable-sanitizers option.
    public static var enableSanitizersSchemaProperty: [String: Value] {
        [
            "enable_sanitizers": .object([
                "type": .string("boolean"),
                "description": .string(
                    "Enable sanitizers (Thread, Address, Undefined Behavior). "
                        + "Sanitizers significantly slow compilation, so they are disabled "
                        + "by default. Enable when diagnosing memory or concurrency issues.",
                ),
            ]),
        ]
    }

    /// Schema property for xcodebuild build setting overrides.
    ///
    /// Returns the `build_settings` property used across build and test tools.
    public static var buildSettingsSchemaProperty: [String: Value] {
        [
            "build_settings": .object([
                "type": .string("object"),
                "additionalProperties": .object(["type": .string("string")]),
                "description": .string(
                    "Xcodebuild build setting overrides (key-value pairs). "
                        + "Each entry is appended as KEY=VALUE to the xcodebuild invocation, "
                        + "taking highest precedence in setting resolution. "
                        + "Example: {\"SWIFT_ENABLE_EXPLICIT_MODULES\": \"NO\"}",
                ),
            ]),
        ]
    }

    /// Schema properties for test selection and coverage parameters.
    ///
    /// Returns the common `only_testing`, `skip_testing`, `enable_code_coverage`,
    /// and `result_bundle_path` properties used across test tools.
    public static var testSchemaProperties: [String: Value] {
        [
            "only_testing": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Test identifiers to run exclusively. Format: 'TargetName/TestClass/testMethod'. "
                        + "For Swift Testing functions with backtick-escaped names containing spaces, "
                        + "use the format 'TargetName/TestClass/`method name with spaces`()'. "
                        + "If backticks are omitted from names with spaces, they are added automatically. "
                        +
                        "Single-word Swift keywords (e.g. 'class', 'import') are also auto-wrapped.",
                ),
            ]),
            "skip_testing": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Test identifiers to skip. Same format as only_testing.",
                ),
            ]),
            "enable_code_coverage": .object([
                "type": .string("boolean"),
                "description": .string(
                    "Enable code coverage collection. Defaults to false.",
                ),
            ]),
            "result_bundle_path": .object([
                "type": .string("string"),
                "description": .string(
                    "Path to store the .xcresult bundle for coverage and test results.",
                ),
            ]),
            "test_plan": .object([
                "type": .string("string"),
                "description": .string(
                    "Name of the test plan to use (e.g. 'Performance'). Overrides the scheme's default test plan. Use list_test_plan_targets to discover available test plans.",
                ),
            ]),
            "timeout": .object([
                "type": .string("integer"),
                "description": .string(
                    "Maximum time in seconds for the test run. Defaults to 300 (5 minutes).",
                ),
            ]),
            "output_timeout": .object([
                "type": .string("integer"),
                "description": .string(
                    "Maximum seconds to wait without output before assuming the process is stuck. Defaults to 120 for test commands. Set to 0 to disable. XCUI and performance tests may need higher values.",
                ),
            ]),
        ]
    }

    /// Resolves a target PID from arguments, checking `pid` first, then falling back to
    /// `bundle_id` lookup via `PIDResolver` (NSRunningApplication).
    ///
    /// Use this for standalone diagnostic tools (leaks, heap, vmmap, etc.) that don't
    /// require an active LLDB session.
    ///
    /// - Returns: The resolved process ID.
    /// - Throws: ``MCPError/invalidParams(_:)`` if neither `pid` nor a matching `bundle_id` is found.
    public func resolveTargetPID() async throws(MCPError) -> Int32 {
        if let pid = getInt("pid") {
            return Int32(pid)
        }
        if let bundleId = getString("bundle_id"),
           let pid = await MainActor.run(body: { PIDResolver.findPID(forBundleID: bundleId) })
        {
            return pid
        }
        throw .invalidParams(
            "Either pid or bundle_id (of a running app) is required",
        )
    }

    /// Resolves a target PID from arguments, checking `pid` first, then falling back to
    /// `bundle_id` lookup via LLDBSessionManager.
    ///
    /// - Returns: The resolved process ID.
    /// - Throws: ``MCPError/invalidParams(_:)`` if neither `pid` nor a valid `bundle_id` session is available.
    public func resolveDebugPID() async throws(MCPError) -> Int32 {
        var pid = getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw .invalidParams(
                "Either pid or bundle_id (with active session) is required",
            )
        }
        return targetPID
    }

    /// Parses batch translation entries from an "entries" array argument.
    ///
    /// Each entry must be an object with a "key" string and a "translations" object
    /// mapping language codes to translated strings.
    ///
    /// - Returns: An array of ``BatchTranslationEntry`` values.
    /// - Throws: MCPError.invalidParams if the structure is invalid.
    public func parseBatchTranslationEntries() throws -> [BatchTranslationEntry] {
        guard case let .array(entriesArray) = self["entries"] else {
            throw MCPError.invalidParams("entries must be an array")
        }

        return try entriesArray.compactMap { entryValue -> BatchTranslationEntry? in
            guard case let .object(entry) = entryValue,
                  case let .string(key) = entry["key"],
                  case let .object(translationsObj) = entry["translations"]
            else {
                throw MCPError.invalidParams(
                    "Each entry must have a 'key' string and 'translations' object",
                )
            }

            var translations: [String: String] = [:]
            for (lang, val) in translationsObj {
                if case let .string(str) = val {
                    translations[lang] = str
                }
            }

            guard !translations.isEmpty else {
                throw MCPError.invalidParams(
                    "translations for key '\(key)' must contain at least one language",
                )
            }

            return BatchTranslationEntry(key: key, translations: translations)
        }
    }
}
