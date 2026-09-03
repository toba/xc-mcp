import MCP
import Foundation

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
        if case let .string(value) = self[key] { return value }
        return nil
    }

    /// Extracts an optional string value for the given key, treating an empty string as absent
    ///
    /// A filter argument reads better this way. An empty string narrows nothing, so a caller that
    /// sends one means the same as a caller that sends no key at all.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The string value, or `nil` when the key is missing, not a string, or empty.
    public func getNonEmptyString(_ key: String) -> String? {
        guard let value = getString(key), !value.isEmpty else { return nil }
        return value
    }

    /// Extracts a required string value for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The string value.
    /// - Throws: MCPError.invalidParams if the key is missing or not a string.
    public func getRequiredString(_ key: String) throws(MCPError) -> String {
        guard case let .string(value) = self[key] else {
            throw .invalidParams("\(key) is required")
        }
        return value
    }

    /// Extracts the `platform` argument as an ``ApplePlatform``
    ///
    /// An unrecognized name is rejected rather than mapped to a fallback. A silent fallback writes
    /// the deployment target under the wrong build setting key, and the target then builds against
    /// the SDK default instead of the version the caller asked for.
    ///
    /// - Parameter defaultPlatform: The platform to use when the caller omits the key.
    /// - Returns: The parsed platform.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the value names no known platform.
    public func getPlatform(
        default defaultPlatform: ApplePlatform = .iOS,
    ) throws(MCPError) -> ApplePlatform {
        guard let name = getString("platform") else { return defaultPlatform }
        guard let platform = ApplePlatform(rawValue: name) else {
            throw .invalidParams(
                "Unknown platform: \(name). Expected one of \(ApplePlatform.allNames)",
            )
        }
        return platform
    }

    /// Schema property for the target platform, listing every ``ApplePlatform`` case.
    public static var platformSchemaProperty: [String: Value] {
        [
            "platform": .object([
                "type": .string("string"),
                "enum": .array(ApplePlatform.allCases.map { .string($0.rawValue) }),
                "description": .string("Platform (\(ApplePlatform.allNames)). Defaults to iOS"),
            ])
        ]
    }

    /// Extracts an optional boolean value for the given key.
    ///
    /// - Parameters:
    ///   - key: The argument key to look up.
    ///   - defaultValue: The value to return if the key is missing. Defaults to false.
    /// - Returns: The boolean value if present, or the default value.
    public func getBool(_ key: String, default defaultValue: Bool = false) -> Bool {
        if case let .bool(value) = self[key] { return value }
        return defaultValue
    }

    /// Extracts a boolean value for the given key, distinguishing absence from false
    ///
    /// Use this where the three states differ. A tool that leaves a build setting alone when the
    /// caller omits the key, and writes it otherwise, needs the `nil` case. Where a missing key
    /// means one fixed value, call ``getBool(_:default:)`` instead.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The boolean value, or `nil` when the key is missing or not a boolean.
    public func getOptionalBool(_ key: String) -> Bool? {
        if case let .bool(value) = self[key] { return value }
        return nil
    }

    /// Extracts an optional integer value for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The integer value if present and valid, nil otherwise.
    public func getInt(_ key: String) -> Int? {
        switch self[key] {
            case let .int(value): value
            case let .double(value) where value == value.rounded(): Int(value)
            default: nil
        }
    }

    /// Extracts an optional double value for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The double value if present and valid, nil otherwise.
    public func getDouble(_ key: String) -> Double? {
        switch self[key] {
            case let .double(value): value
            case let .int(value): Double(value)
            default: nil
        }
    }

    /// Extracts a required double value for the given key.
    ///
    /// Accepts an integer as well, the same as ``getDouble(_:)`` , because a JSON client sends `0`
    /// rather than `0.0` for a whole number.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The double value.
    /// - Throws: MCPError.invalidParams if the key is missing or holds no number.
    public func getRequiredDouble(_ key: String) throws(MCPError) -> Double {
        guard let value = getDouble(key) else {
            throw .invalidParams("\(key) is required and must be a number")
        }
        return value
    }

    /// Extracts a string-to-string dictionary for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: A dictionary of string key-value pairs. Returns empty dictionary if key is
    ///   missing or not an object.
    public func getStringDictionary(_ key: String) -> [String: String] {
        guard case let .object(obj) = self[key] else { return [:] }
        return Self.stringValues(from: obj)
    }

    /// Collects the `.string`-valued entries of an MCP `Value` object into `[String: String]` ,
    /// dropping any non-string values.
    static func stringValues(from object: [String: Value]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(object.count)
        for (k, v) in object { if case let .string(s) = v { result[k] = s } }
        return result
    }

    /// Extracts xcodebuild build setting overrides and returns them as `["KEY=VALUE", ...]` .
    ///
    /// - Parameter key: The argument key to look up. Defaults to `"build_settings"` .
    /// - Returns: An array of `KEY=VALUE` strings suitable for xcodebuild positional arguments.
    public func buildSettingOverrides(_ key: String = "build_settings") -> [String] {
        getStringDictionary(key).map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// Extracts a string array for the given key.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: An array of strings. Returns empty array if key is missing or not an array.
    public func getStringArray(_ key: String) -> [String] {
        guard case let .array(array) = self[key] else { return [] }
        return array.compactMap { value in
            if case let .string(s) = value { return s }
            return nil
        }
    }

    /// Extracts a string array for the given key, distinguishing absence from an empty array
    ///
    /// Use this where the caller clears a field by sending `[]` and leaves it alone by sending no
    /// key. ``getStringArray(_:)`` collapses both to an empty array, which loses that distinction.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The strings in the array, or `nil` when the key is missing or holds no array.
    ///   Non-string elements are dropped.
    public func getOptionalStringArray(_ key: String) -> [String]? {
        guard case .array = self[key] else { return nil }
        return getStringArray(key)
    }

    /// Extracts an argument that takes either one string or a list of them.
    ///
    /// Use this where the underlying option repeats, such as a filter pattern. A caller naturally
    /// writes one value as a bare string, and both shapes then reach the same list.
    ///
    /// - Parameter key: The argument key to look up.
    /// - Returns: The values, empty when the key is absent. Empty strings are dropped.
    public func getStringList(_ key: String) -> [String] {
        if let single = getNonEmptyString(key) { return [single] }
        return getStringArray(key).filter { !$0.isEmpty }
    }

    /// Extracts test selection and coverage parameters from arguments.
    ///
    /// Normalizes test identifiers that use Swift Testing backtick-escaped names. If a method
    /// component contains spaces but is missing backticks and trailing `()` , they are added
    /// automatically so xcodebuild can match them.
    public func testParameters() -> TestParameters {
        let onlyTestingArray = getStringArray("only_testing").map(Self.normalizeTestIdentifier)
        let skipTestingArray = getStringArray("skip_testing").map(Self.normalizeTestIdentifier)
        return .init(
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
    /// This also handles single-word Swift keywords used as test names (e.g. `class` , `import` )
    /// which need backtick wrapping even though they contain no spaces.
    private static func normalizeTestIdentifier(_ identifier: String) -> String {
        // Split into components: Target/Class/Method
        let parts = identifier.split(separator: "/", maxSplits: 2)
        guard parts.count == 3 else { return identifier }

        let method = parts[2]

        // Already backtick-wrapped — ensure () suffix
        if method.hasPrefix("`") {
            return method.hasSuffix("()") ? identifier : "\(parts[0])/\(parts[1])/\(method)()"
        }

        let needsBackticks = method.contains(" ") || swiftKeywords.contains(String(method))

        guard needsBackticks else { return identifier }

        // Wrap in backticks and add () if missing
        var normalized = "`\(method)`"
        if !method.hasSuffix("()") { normalized += "()" }
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

    /// Resolves the no-output ("stuck process") budget for a build or query tool.
    ///
    /// The precedence is:
    /// 1. An explicit `output_timeout` wins. Any value at or below `0` disables the check. A
    ///    negative budget would otherwise fire on the first watchdog tick and report a stuck build
    ///    that never stalled.
    /// 2. An explicit `timeout` with no `output_timeout` disables the check. A caller who sets an
    ///    overall budget has already bounded the run, so the silence heuristic only adds a way to
    ///    kill a build that is still making progress.
    /// 3. Otherwise the supplied default applies.
    ///
    /// The Swift package resolution phase gets a wider floor inside the runner regardless of this
    /// value. See ``XcodebuildRunner/packageResolutionOutputTimeout``.
    ///
    /// - Parameter defaultTimeout: The budget to use when the caller supplies neither parameter.
    /// - Returns: The budget, or `nil` when the silence check is off.
    public func resolveOutputTimeout(default defaultTimeout: Duration) -> Duration? {
        if let seconds = getInt("output_timeout") { return seconds <= 0 ? nil : .seconds(seconds) }
        return self["timeout"] != nil ? nil : defaultTimeout
    }

    /// Extracts the caller's `timeout` argument as a `Duration`, or `nil` when they omit it.
    ///
    /// A tool that picks its fallback from context, such as a cold build cache, has to tell an
    /// explicit value from an absent one. Those tools take the optional and branch on it. Every
    /// other tool takes ``resolveTimeout(default:)-(Duration)`` instead.
    public func explicitTimeout() -> Duration? { getInt("timeout").map { Duration.seconds($0) } }

    /// Resolves the overall run budget as a `Duration`, the unit ``SwiftRunner`` takes.
    ///
    /// - Parameter defaultTimeout: The budget to use when the caller omits `timeout`.
    public func resolveTimeout(default defaultTimeout: Duration) -> Duration {
        explicitTimeout() ?? defaultTimeout
    }

    /// Resolves the overall run budget as a `TimeInterval`, the unit ``XcodebuildRunner`` takes.
    ///
    /// - Parameter defaultTimeout: The budget to use when the caller omits `timeout`.
    public func resolveTimeout(default defaultTimeout: TimeInterval) -> TimeInterval {
        getInt("timeout").map(TimeInterval.init) ?? defaultTimeout
    }

    /// Schema property for the overall run budget.
    ///
    /// - Parameters:
    ///   - defaultSeconds: The budget the tool applies when the caller omits the parameter.
    ///   - subject: The noun the description uses for the run, such as "build" or "archive".
    public static func timeoutSchemaProperty(
        defaultSeconds: Int,
        subject: String = "build",
    ) -> [String: Value] {
        [
            "timeout": .object([
                "type": .string("integer"),
                "description": .string(
                    "Maximum time in seconds for the \(subject). "
                        + "Defaults to \(defaultSeconds). "
                        + "Setting it also turns off the no-output check unless output_timeout "
                        + "is given. When the \(subject) times out, partial diagnostics collected "
                        + "so far are returned instead of an empty error.",
                ),
            ])
        ]
    }

    /// Schema property for the no-output ("stuck process") budget.
    ///
    /// Every build and query tool exposes this property with the same meaning the test tools give
    /// it. Pair it with ``resolveOutputTimeout(default:)`` to read the value.
    ///
    /// - Parameters:
    ///   - defaultSeconds: The budget the tool applies when the caller omits the parameter.
    ///   - note: An extra sentence appended to the description.
    public static func outputTimeoutSchemaProperty(
        defaultSeconds: Int,
        note: String = "",
    ) -> [String: Value] {
        // Read the resolution floor from the runner constant. A hardcoded count would leave this
        // sentence wrong in every tool at once the moment the constant moves.
        let resolutionSeconds = XcodebuildRunner.packageResolutionOutputTimeout.components.seconds
        var description =
            "Maximum seconds to wait without output before assuming the process is stuck. "
            + "Defaults to \(defaultSeconds). Set to 0 to disable. "
            + "Swift package resolution is silent by design, so that phase always gets at least "
            + "\(resolutionSeconds) seconds and the overall timeout governs it."
        if !note.isEmpty { description += " " + note }
        return [
            "output_timeout": .object([
                "type": .string("integer"),
                "description": .string(description),
            ])
        ]
    }

    /// Schema property for the no-output budget on a tool that queries a project.
    ///
    /// Shared by `list_schemes`, `show_build_settings` and `list_test_plan_targets`. All three hit
    /// the same wall: the query prints nothing until package resolution finishes, so the caller
    /// needs the same guidance in all three descriptions.
    public static var queryOutputTimeoutSchemaProperty: [String: Value] {
        outputTimeoutSchemaProperty(
            defaultSeconds: 30,
            note: "A project with unresolved packages prints nothing until resolution finishes.",
        )
    }

    /// Schema property for the errors-only result mode.
    ///
    /// Every build, test, archive and diagnostic tool exposes this property with the same meaning.
    /// Pair it with `getBool("errors_only")` to read the value.
    ///
    /// - Parameter note: An extra sentence appended to the description.
    public static func errorsOnlySchemaProperty(note: String = "") -> [String: Value] {
        var description =
            "When true, leave every warning out of the result and report the errors alone. "
            + "A failed build of a wide refactor carries hundreds of warnings, and they crowd the "
            + "errors out of the response. Defaults to false."
        if !note.isEmpty { description += " " + note }
        return [
            "errors_only": .object([
                "type": .string("boolean"), "description": .string(description),
            ])
        ]
    }

    /// Returns the `-IDEBuildingContinueBuildingAfterErrors` flag for the requested mode.
    ///
    /// xcodebuild stops on the first build error, so a caller who reads only that error learns one
    /// file name per build. A refactor that breaks twenty files then costs twenty builds. The flag
    /// goes on unless the caller asks for the stop, which matches what `swift build` does through
    /// `SwiftRunner.continueAfterErrorsArguments`. Opting out passes nothing, because stopping is
    /// what xcodebuild does on its own.
    public func continueBuildingArgs() -> [String] {
        getBool("continue_building_after_errors", default: true)
            ? ["-IDEBuildingContinueBuildingAfterErrors=YES"]
            : []
    }

    /// Schema property for the continue-building-after-errors option.
    ///
    /// Maps to Xcode's "Continue building after errors" preference (
    /// `-IDEBuildingContinueBuildingAfterErrors` ). One key, one default, across every server that
    /// builds.
    public static var continueBuildingSchemaProperty: [String: Value] {
        [
            "continue_building_after_errors": .object([
                "type": .string("boolean"),
                "description": .string(
                    "When true, the build keeps going after an error, so one call names every "
                        + "broken file instead of the first one alone. Maps to Xcode's "
                        + "'Continue building after errors' setting. "
                        + "Defaults to true. Pass false to stop at the first error.",
                ),
            ])
        ]
    }

    /// Returns build setting overrides to disable all sanitizers unless explicitly enabled.
    ///
    /// Disables Thread Sanitizer, Address Sanitizer, and Undefined Behavior Sanitizer by default.
    /// Sanitizers significantly slow compilation, so they are opt-in.
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
            ])
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
            ])
        ]
    }

    /// Schema property for extra passthrough xcodebuild arguments.
    ///
    /// Returns the `extra_args` property used across build and test tools. When provided, it
    /// replaces (does not append to) the session default set via `set_session_defaults` .
    public static var extraArgsSchemaProperty: [String: Value] {
        [
            "extra_args": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Extra arguments appended verbatim to the xcodebuild invocation "
                        + "(e.g. [\"-skipPackagePluginValidation\"]). Each element is passed as a "
                        + "separate argument. Overrides any extra_args session default for this "
                        + "call; use set_session_defaults to persist them across calls.",
                ),
            ])
        ]
    }

    /// Schema property for the without-building (reuse-prepared-artifacts) option.
    ///
    /// Maps to xcodebuild's `test-without-building` action.
    public static var withoutBuildingSchemaProperty: [String: Value] {
        [
            "without_building": .object([
                "type": .string("boolean"),
                "description": .string(
                    "When true, skip the build phase and run the test bundle already compiled "
                        + "by a prior build or test run (xcodebuild 'test-without-building'). "
                        + "Reuses artifacts from the same project's scoped DerivedData, so run a "
                        + "normal test (or build_macos with for_testing) at least once first. "
                        + "Speeds up repeated runs by skipping build planning and compilation; "
                        + "fails if no compiled products exist yet. Defaults to false.",
                ),
            ])
        ]
    }

    /// Schema properties for test selection and coverage parameters.
    ///
    /// Returns the common `only_testing` , `skip_testing` , `enable_code_coverage` , and
    /// `result_bundle_path` properties used across test tools.
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
                        + "Single-word Swift keywords (e.g. 'class', 'import') are also auto-wrapped.",
                ),
            ]),
            "skip_testing": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string("Test identifiers to skip. Same format as only_testing."),
            ]),
            "enable_code_coverage": .object([
                "type": .string("boolean"),
                "description": .string("Enable code coverage collection. Defaults to false."),
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
        ].merging(outputTimeoutSchemaProperty(
            defaultSeconds: 120, note: "XCUI and performance tests may need higher values.",
        ),
        ) { _, new in new }
    }

    /// Resolves a target PID from arguments, checking `pid` first, then falling back to `bundle_id`
    /// lookup via `PIDResolver` (NSRunningApplication).
    ///
    /// Use this for standalone diagnostic tools (leaks, heap, vmmap, etc.) that don't require an
    /// active LLDB session.
    ///
    /// - Returns: The resolved process ID.
    /// - Throws: ``MCPError/invalidParams(_:)`` if neither `pid` nor a matching `bundle_id` is
    ///   found.
    public func resolveTargetPID() async throws(MCPError) -> Int32 {
        if let pid = getInt("pid") { return Int32(pid) }

        if let bundleID = getString("bundle_id"),
           let pid = await MainActor.run(body: { PIDResolver.findPID(forBundleID: bundleID) }) {
            return pid
        }
        throw .invalidParams("Either pid or bundle_id (of a running app) is required")
    }

    /// Resolves a target PID from arguments, checking `pid` first, then falling back to `bundle_id`
    /// lookup via LLDBSessionManager.
    ///
    /// - Returns: The resolved process ID.
    /// - Throws: ``MCPError/invalidParams(_:)`` if neither `pid` nor a valid `bundle_id` session is
    ///   available.
    public func resolveDebugPID() async throws(MCPError) -> Int32 {
        var pid = getInt("pid").map(Int32.init)

        if pid == nil, let bundleID = getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleID: bundleID)
        }

        guard let targetPID = pid else {
            throw .invalidParams("Either pid or bundle_id (with active session) is required")
        }
        return targetPID
    }

    /// Parses batch translation entries from an "entries" array argument.
    ///
    /// Each entry must be an object with a "key" string and a "translations" object mapping
    /// language codes to translated strings.
    ///
    /// - Returns: An array of ``BatchTranslationEntry`` values.
    /// - Throws: MCPError.invalidParams if the structure is invalid.
    public func parseBatchTranslationEntries() throws(MCPError) -> [BatchTranslationEntry] {
        guard case let .array(entriesArray) = self["entries"] else {
            throw .invalidParams("entries must be an array")
        }

        var entries: [BatchTranslationEntry] = []
        entries.reserveCapacity(entriesArray.count)

        for entryValue in entriesArray {
            guard case let .object(entry) = entryValue,
                  case let .string(key) = entry["key"],
                  case let .object(translationsObj) = entry["translations"]
            else {
                throw .invalidParams(
                    "Each entry must have a 'key' string and 'translations' object",
                )
            }

            let translations = Self.stringValues(from: translationsObj)
            guard !translations.isEmpty else {
                throw .invalidParams(
                    "translations for key '\(key)' must contain at least one language",
                )
            }

            entries.append(BatchTranslationEntry(key: key, translations: translations))
        }
        return entries
    }
}
