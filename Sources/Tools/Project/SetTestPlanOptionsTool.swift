import MCP
import XCMCPCore
import Foundation

/// Edits a test plan's per-configuration `options` block or plan-level `defaultOptions`.
///
/// Covers the option keys the sibling `SetTestPlan*Tool` tools don't reach —
/// `diagnosticCollectionPolicy`, `userAttachmentLifetime`, `uiTestingScreenshotsLifetime`,
/// `codeCoverage`, and `mainThreadCheckerEnabled`. Only the keys explicitly provided are written;
/// everything else in the target options block is left untouched. Keys can be reset to the plan
/// default by listing them in `clear`.
public struct SetTestPlanOptionsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    /// A supported option: the JSON key plus its allowed enum values (empty for booleans).
    private struct Option {
        let param: String
        let jsonKey: String
        let values: [String]
    }

    /// Enum-valued options, keyed by the tool parameter name.
    private static let enumOptions: [Option] = [
        Option(
            param: "diagnostic_collection_policy",
            jsonKey: "diagnosticCollectionPolicy",
            values: ["Always", "OnFailure", "Never"],
        ),
        Option(
            param: "user_attachment_lifetime",
            jsonKey: "userAttachmentLifetime",
            values: ["keepNever", "keepAlways", "deleteOnSuccess"],
        ),
        Option(
            param: "ui_testing_screenshots_lifetime",
            jsonKey: "uiTestingScreenshotsLifetime",
            values: ["keepNever", "keepAlways", "deleteOnSuccess"],
        ),
    ]

    /// Boolean-valued options, keyed by the tool parameter name.
    private static let boolOptions: [Option] = [
        Option(param: "code_coverage", jsonKey: "codeCoverage", values: []),
        Option(param: "main_thread_checker_enabled", jsonKey: "mainThreadCheckerEnabled", values: []),
    ]

    /// All settable options, plus a `param -> jsonKey` map used when resolving `clear`.
    private static var allOptions: [Option] { enumOptions + boolOptions }

    public func tool() -> Tool {
        var properties: [String: Value] = [
            "test_plan_path": .object([
                "type": .string("string"),
                "description": .string("Path to the .xctestplan file"),
            ]),
            "configuration_name": .object([
                "type": .string("string"),
                "description": .string(
                    "Name of a configurations[] entry whose 'options' block to edit. "
                        + "If omitted, edits the plan-level 'defaultOptions'.",
                ),
            ]),
            "clear": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Option parameter names to remove from the options block, resetting them to "
                        + "the plan default (e.g. 'code_coverage', 'diagnostic_collection_policy').",
                ),
            ]),
        ]

        for option in Self.enumOptions {
            properties[option.param] = .object([
                "type": .string("string"),
                "enum": .array(option.values.map { .string($0) }),
                "description": .string("Sets '\(option.jsonKey)'."),
            ])
        }
        for option in Self.boolOptions {
            properties[option.param] = .object([
                "type": .string("boolean"),
                "description": .string("Sets '\(option.jsonKey)'."),
            ])
        }

        return Tool(
            name: "set_test_plan_options",
            description:
            "Edit a test plan's per-configuration 'options' block or plan-level 'defaultOptions' "
                + "(diagnosticCollectionPolicy, userAttachmentLifetime, uiTestingScreenshotsLifetime, "
                + "codeCoverage, mainThreadCheckerEnabled). Only the keys you provide are written; "
                + "others are left untouched. Use 'clear' to reset keys to the plan default. "
                + "Lowering diagnosticCollectionPolicy to OnFailure and userAttachmentLifetime to "
                + "keepNever cuts per-test diagnostic overhead.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([.string("test_plan_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let testPlanPath = try arguments.getRequiredString("test_plan_path")
        let configurationName = arguments.getString("configuration_name")

        // Collect the keys to clear, validating each against a known option.
        var clearKeys: [String] = []
        for param in arguments.getStringArray("clear") {
            guard let option = Self.allOptions.first(where: { $0.param == param }) else {
                throw MCPError.invalidParams(
                    "Unknown option '\(param)' in clear. Valid options: "
                        + Self.allOptions.map(\.param).joined(separator: ", "),
                )
            }
            clearKeys.append(option.jsonKey)
        }

        // Collect the keys to set, validating enum values.
        var setValues: [(jsonKey: String, value: Any, display: String)] = []
        for option in Self.enumOptions {
            guard let value = arguments.getString(option.param) else { continue }
            guard option.values.contains(value) else {
                throw MCPError.invalidParams(
                    "\(option.param) must be one of: \(option.values.joined(separator: ", "))",
                )
            }
            setValues.append((option.jsonKey, value, "\(option.jsonKey)=\(value)"))
        }
        for option in Self.boolOptions {
            guard case let .bool(value) = arguments[option.param] else { continue }
            setValues.append((option.jsonKey, value, "\(option.jsonKey)=\(value)"))
        }

        guard !setValues.isEmpty || !clearKeys.isEmpty else {
            throw MCPError.invalidParams(
                "Provide at least one option to set, or keys to clear.",
            )
        }

        let resolvedPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedPath)

            try mutateOptions(&json, configurationName: configurationName) { options in
                for key in clearKeys { options.removeValue(forKey: key) }
                for entry in setValues { options[entry.jsonKey] = entry.value }
            }

            try TestPlanFile.write(json, to: resolvedPath)

            let scope = configurationName.map { "configuration '\($0)'" } ?? "plan-level defaultOptions"
            var changes: [String] = []
            if !setValues.isEmpty {
                changes.append("set \(setValues.map(\.display).joined(separator: ", "))")
            }
            if !clearKeys.isEmpty {
                changes.append("cleared \(clearKeys.joined(separator: ", "))")
            }
            return CallTool.Result(
                content: [
                    .text(
                        text: "Updated \(scope) in \(resolvedPath): \(changes.joined(separator: "; "))",
                        annotations: nil,
                        _meta: nil,
                    ),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to update test plan options: \(error.localizedDescription)",
            )
        }
    }

    /// Applies `transform` to the target options dictionary — either a named configuration's
    /// `options` block or the plan-level `defaultOptions`.
    private func mutateOptions(
        _ json: inout [String: Any],
        configurationName: String?,
        _ transform: (inout [String: Any]) -> Void,
    ) throws(MCPError) {
        guard let configurationName else {
            var defaults = json["defaultOptions"] as? [String: Any] ?? [:]
            transform(&defaults)
            json["defaultOptions"] = defaults
            return
        }

        guard var configurations = json["configurations"] as? [[String: Any]] else {
            throw MCPError.invalidParams("Test plan has no configurations")
        }
        guard
            let index = configurations.firstIndex(where: {
                $0["name"] as? String == configurationName
            })
        else {
            let names = configurations.compactMap { $0["name"] as? String }.joined(separator: ", ")
            throw MCPError.invalidParams(
                "Configuration '\(configurationName)' not found in test plan."
                    + (names.isEmpty ? "" : " Available: \(names)"),
            )
        }

        var entry = configurations[index]
        var options = entry["options"] as? [String: Any] ?? [:]
        transform(&options)
        entry["options"] = options
        configurations[index] = entry
        json["configurations"] = configurations
    }
}
