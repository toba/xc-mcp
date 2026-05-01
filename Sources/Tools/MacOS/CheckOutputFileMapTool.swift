import MCP
import XCMCPCore
import Foundation

/// Compares a target's OutputFileMap.json against actual files on disk in DerivedData.
///
/// Reports which source files compiled successfully (produced a .o file) and which
/// did not. This is the fastest way to find silent compiler crashes — the compiler
/// dies mid-compilation, so some .o files simply never get written.
public struct CheckOutputFileMapTool: Sendable {
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
            name: "check_output_file_map",
            description:
            "Compare a target's OutputFileMap.json against actual .o files on disk. "
                + "Identifies source files whose object files are missing — the hallmark "
                + "of a silent compiler crash where the compiler dies mid-compilation.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Target name to check. Required.",
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
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug.",
                        ),
                    ]),
                ]),
                "required": .array([.string("target")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let target = try arguments.getRequiredString("target")
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)

        let projectRoot = try await DerivedDataLocator.findProjectRoot(
            xcodebuildRunner: xcodebuildRunner,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            configuration: configuration,
        )

        let intermediates = DerivedDataLocator.intermediatesPath(projectRoot: projectRoot)

        // Find OutputFileMap.json for the target
        let outputFileMapPath = try findOutputFileMap(
            intermediatesDir: intermediates, target: target,
        )

        // Parse the OutputFileMap
        let data = try Data(contentsOf: URL(fileURLWithPath: outputFileMapPath))
        guard
            let fileMap = try JSONSerialization
            .jsonObject(with: data) as? [String: [String: String]]
        else {
            throw MCPError.internalError(
                "Could not parse OutputFileMap.json at \(outputFileMapPath)",
            )
        }

        // Check each source file's expected .o file
        let fm = FileManager.default
        var missing: [(source: String, objectFile: String)] = []
        var present: [String] = []
        var totalSources = 0

        for (source, outputs) in fileMap.sorted(by: { $0.key < $1.key }) {
            // Skip the empty-string master entry
            guard !source.isEmpty else { continue }

            guard let objectFile = outputs["object"] else { continue }
            totalSources += 1

            if fm.fileExists(atPath: objectFile) {
                present.append(source)
            } else {
                missing.append((source: source, objectFile: objectFile))
            }
        }

        // Format output
        var text = "## Output File Map Check: \(target)\n\n"
        text += "**OutputFileMap:** \(outputFileMapPath)\n"
        text += "**Sources:** \(totalSources) total, \(present.count) compiled, "
        text += "\(missing.count) missing .o files\n\n"

        if missing.isEmpty {
            text += "All source files compiled successfully — no missing object files."
        } else {
            text += "### Missing Object Files\n\n"
            text +=
                "These source files have no .o file, indicating the compiler crashed or was "
                + "killed before completing them:\n\n"
            for entry in missing {
                let sourceName = URL(fileURLWithPath: entry.source).lastPathComponent
                text += "- **\(sourceName)**\n"
                text += "  Source: \(entry.source)\n"
                text += "  Expected: \(entry.objectFile)\n"
            }
        }

        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - Private

    private func findOutputFileMap(
        intermediatesDir: String, target: String,
    ) throws -> String {
        let fm = FileManager.default

        // Walk intermediates looking for <target>.build/*/OutputFileMap.json
        guard let enumerator = fm.enumerator(atPath: intermediatesDir) else {
            throw MCPError.internalError(
                "Could not enumerate intermediates directory: \(intermediatesDir)",
            )
        }

        var candidates: [(path: String, date: Date)] = []
        while let element = enumerator.nextObject() as? String {
            let pathComponent = (element as NSString).lastPathComponent
            if pathComponent == "OutputFileMap.json",
               element.contains("\(target).build")
            {
                let fullPath = (intermediatesDir as NSString).appendingPathComponent(element)
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let date = attrs[.modificationDate] as? Date
                {
                    candidates.append((path: fullPath, date: date))
                }
            }
        }

        guard let newest = candidates.max(by: { $0.date < $1.date }) else {
            throw MCPError.internalError(
                "No OutputFileMap.json found for target '\(target)' in \(intermediatesDir). "
                    + "Has the project been built at least once?",
            )
        }

        return newest.path
    }
}
