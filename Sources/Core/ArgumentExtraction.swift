import MCP

/// Holds extracted test selection and coverage parameters.
public struct TestParameters: Sendable {
    public let onlyTesting: [String]?
    public let skipTesting: [String]?
    public let enableCodeCoverage: Bool
    public let resultBundlePath: String?
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
        if case let .int(value) = self[key] {
            return value
        }
        return nil
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
    public func testParameters() -> TestParameters {
        let onlyTestingArray = getStringArray("only_testing")
        let skipTestingArray = getStringArray("skip_testing")
        return TestParameters(
            onlyTesting: onlyTestingArray.isEmpty ? nil : onlyTestingArray,
            skipTesting: skipTestingArray.isEmpty ? nil : skipTestingArray,
            enableCodeCoverage: getBool("enable_code_coverage"),
            resultBundlePath: getString("result_bundle_path")
        )
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
                    "Test identifiers to run exclusively (e.g., 'MyTests/testFoo')."),
            ]),
            "skip_testing": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Test identifiers to skip."),
            ]),
            "enable_code_coverage": .object([
                "type": .string("boolean"),
                "description": .string(
                    "Enable code coverage collection. Defaults to false."),
            ]),
            "result_bundle_path": .object([
                "type": .string("string"),
                "description": .string(
                    "Path to store the .xcresult bundle for coverage and test results."),
            ]),
        ]
    }
}
