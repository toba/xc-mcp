import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct BuildMacOSTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "build_macos",
            description: "Build an Xcode project or workspace for macOS.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(
                    [
                        "project_path": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Path to the .xcodeproj file. Uses session default if not specified.",
                            ),
                        ]),
                        "workspace_path": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Path to the .xcworkspace file. Uses session default if not specified.",
                            ),
                        ]),
                        "scheme": .object([
                            "type": .string("string"),
                            "description": .string(
                                "The scheme to build. Uses session default if not specified.",
                            ),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug.",
                            ),
                        ]),
                        "arch": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Architecture to build for (arm64 or x86_64). Defaults to the current machine's architecture.",
                            ),
                        ]),
                        "show_warnings": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When true, include detailed compiler warnings in the output. By default, successful builds only report the warning count in the summary header.",
                            ),
                        ]),
                        "for_testing": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "When true, runs 'build-for-testing' instead of 'build'. This compiles all test targets without executing them — useful for verifying test code compiles before committing to a full test run.",
                            ),
                        ]),
                        "timeout": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Maximum time in seconds for the build. Defaults to 300 (5 minutes). "
                                    + "When the build times out, partial diagnostics (errors and warnings "
                                    + "collected so far) are returned instead of an empty error.",
                            ),
                        ]),
                    ].merging([String: Value].errorsOnlySchemaProperty()) { _, new in new }
                        .merging([String: Value].continueBuildingSchemaProperty) { _, new in new }
                        .merging([String: Value].enableSanitizersSchemaProperty) { _, new in new }
                        .merging([String: Value].buildSettingsSchemaProperty) { _, new in new }
                        .merging([String: Value].extraArgsSchemaProperty) { _, new in new }
                        .merging([String: Value].outputTimeoutSchemaProperty(defaultSeconds: 30)) {
                            _, new in new
                        },
                ),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let extraArgs = await sessionManager.resolveExtraArgs(from: arguments)
        let arch = arguments.getString("arch")
        let errorsOnly = arguments.getBool("errors_only")
        let showWarnings = arguments.getBool("show_warnings")
        let forTesting = arguments.getBool("for_testing")
        let timeout = arguments.resolveTimeout(default: XcodebuildRunner.defaultTimeout)

        let outputTimeout = arguments.resolveOutputTimeout(default: XcodebuildRunner.outputTimeout)

        let projectRoot = ErrorExtractor.projectRoot(
            projectPath: projectPath, workspacePath: workspacePath,
        )

        var destination = XcodebuildRunner.macOSDestination
        if let arch { destination += ",arch=\(arch)" }

        let additionalArguments = arguments.continueBuildingArgs()
            + arguments.enableSanitizersArgs() + arguments.buildSettingOverrides() + extraArgs
        let derivedDataNote = DerivedDataScoper.note(
            workspacePath: workspacePath,
            projectPath: projectPath,
            destination: destination,
            additionalArguments: additionalArguments,
        )

        do {
            try await BuildSettingExtractor.validateMacOSSupport(
                runner: xcodebuildRunner,
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                outputTimeout: outputTimeout,
            )

            let action = forTesting ? "build-for-testing" : "build"

            let result = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                action: action,
                additionalArguments: additionalArguments,
                environment: environment,
                timeout: timeout,
                outputTimeout: outputTimeout,
            )

            try ErrorExtractor.checkBuildSuccess(
                result, projectRoot: projectRoot, errorsOnly: errorsOnly,
                derivedDataNote: derivedDataNote,
            )

            let label = forTesting ? "Build-for-testing" : "Build"
            let summary = ErrorExtractor.extractBuildErrors(
                from: result.output, projectRoot: projectRoot, errorsOnly: errorsOnly,
                showWarnings: showWarnings,
            )
            var text = "\(label) succeeded for scheme '\(scheme)' on macOS"
            if !summary.isEmpty, summary != "Build succeeded" { text += "\n\n" + summary }
            text += "\n\n" + derivedDataNote
            return CallTool.Result.text(text)
        } catch let error as XcodebuildError {
            return error.formatPartialDiagnostics(
                projectRoot: projectRoot, errorsOnly: errorsOnly, showWarnings: showWarnings,
                derivedDataNote: derivedDataNote,
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
