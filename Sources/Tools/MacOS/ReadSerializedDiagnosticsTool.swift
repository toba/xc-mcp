import MCP
import XCMCPCore
import Foundation

/// Reads Swift/Clang serialized diagnostics (.dia) files from DerivedData.
///
/// These binary files are the ground truth for what the compiler actually reported,
/// even when the build log is empty or truncated. Uses `c-index-test` to decode them.
public struct ReadSerializedDiagnosticsTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "read_serialized_diagnostics",
            description:
            "Decode serialized diagnostics (.dia) files from DerivedData. "
                + "These binary files contain the compiler's actual error/warning/note "
                + "messages and exist even when the build log is empty or truncated. "
                + "Provide either a target name (to find .dia files automatically) "
                + "or an explicit file path.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Target name to find .dia files for. Searches DerivedData automatically.",
                        ),
                    ]),
                    "dia_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Explicit path to a .dia file to decode. Overrides target-based search.",
                        ),
                    ]),
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
                            "The scheme to resolve DerivedData from. Uses session default if not specified.",
                        ),
                    ]),
                    "errors_only": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, only show errors (suppress warnings and notes). Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let errorsOnly = arguments.getBool("errors_only")
        var diaPaths: [String] = []

        if let explicitPath = arguments.getString("dia_path") {
            guard FileManager.default.fileExists(atPath: explicitPath) else {
                throw MCPError.invalidParams("File not found: \(explicitPath)")
            }
            diaPaths = [explicitPath]
        } else if let target = arguments.getString("target") {
            let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
                from: arguments,
            )
            let scheme = try await sessionManager.resolveScheme(from: arguments)

            let projectRoot = try await DerivedDataLocator.findProjectRoot(
                xcodebuildRunner: xcodebuildRunner,
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
            )

            let intermediates = DerivedDataLocator.intermediatesPath(projectRoot: projectRoot)
            diaPaths = findDiaFiles(intermediatesDir: intermediates, target: target)

            guard !diaPaths.isEmpty else {
                throw MCPError.internalError(
                    "No .dia files found for target '\(target)' in \(intermediates). "
                        + "Has the project been built at least once?",
                )
            }
        } else {
            throw MCPError.invalidParams(
                "Either 'target' or 'dia_path' is required.",
            )
        }

        // Decode each .dia file using c-index-test
        var allDiagnostics: [(file: String, output: String)] = []

        for path in diaPaths {
            let output = try await decodeDiaFile(at: path)
            if !output.isEmpty {
                allDiagnostics.append(
                    (file: URL(fileURLWithPath: path).lastPathComponent, output: output),
                )
            }
        }

        // Format output
        var text = "## Serialized Diagnostics\n\n"
        text += "Decoded \(diaPaths.count) .dia file(s).\n\n"

        if allDiagnostics.isEmpty {
            text += "No diagnostics found in .dia files."
        } else {
            for diag in allDiagnostics {
                let filtered: String
                if errorsOnly {
                    filtered =
                        diag.output
                            .split(separator: "\n")
                            .filter { $0.contains("error:") }
                            .joined(separator: "\n")
                } else {
                    filtered = diag.output
                }
                guard !filtered.isEmpty else { continue }

                text += "### \(diag.file)\n\n"
                text += "```\n\(filtered)\n```\n\n"
            }
        }

        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - Private

    private func findDiaFiles(intermediatesDir: String, target: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: intermediatesDir) else {
            return []
        }

        var diaFiles: [(path: String, date: Date)] = []
        while let element = enumerator.nextObject() as? String {
            if element.hasSuffix(".dia"),
               element.contains("\(target).build")
            {
                let fullPath = (intermediatesDir as NSString).appendingPathComponent(element)
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let date = attrs[.modificationDate] as? Date
                {
                    diaFiles.append((path: fullPath, date: date))
                }
            }
        }

        // Sort by date descending, limit to 20 most recent
        return diaFiles.sorted { $0.date > $1.date }
            .prefix(20)
            .map(\.path)
    }

    private func decodeDiaFile(at path: String) async throws -> String {
        // c-index-test is the standard tool for reading serialized diagnostics
        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["c-index-test", "-read-diagnostics", path],
            mergeStderr: true,
            timeout: .seconds(10),
        )
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
