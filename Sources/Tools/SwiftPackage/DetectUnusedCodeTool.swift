import MCP
import XCMCPCore
import Foundation

public struct DetectUnusedCodeTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "detect_unused_code",
            description:
            "Detect unused code in a Swift package or Xcode project using Periphery. Returns unused declarations grouped by file. Requires the 'periphery' CLI (brew install periphery).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory. Uses session default if not specified. For SPM projects, this is sufficient — no project or schemes needed.",
                        ),
                    ]),
                    "project": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to .xcodeproj or .xcworkspace. Required for Xcode projects, not needed for SPM packages.",
                        ),
                    ]),
                    "schemes": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Schemes to build and scan. Required for Xcode projects.",
                        ),
                    ]),
                    "retain_public": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Retain all public declarations. Recommended for library/framework projects. Defaults to false.",
                        ),
                    ]),
                    "skip_build": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Skip the build step and use existing index store data. Faster but requires a prior build. Defaults to false.",
                        ),
                    ]),
                    "exclude_targets": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Targets to exclude from indexing.",
                        ),
                    ]),
                    "report_exclude": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "File globs to exclude from results (e.g. \"**/Generated/**\").",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let project = arguments.getString("project")
        let schemes = arguments.getStringArray("schemes")
        let retainPublic = arguments.getBool("retain_public")
        let skipBuild = arguments.getBool("skip_build")
        let excludeTargets = arguments.getStringArray("exclude_targets")
        let reportExclude = arguments.getStringArray("report_exclude")

        let executablePath = try await BinaryLocator.find("periphery")

        var args: [String] = [
            "scan",
            "--format", "json",
            "--quiet",
            "--disable-update-check",
            "--project-root", packagePath,
        ]

        if let project {
            args.append("--project")
            args.append(project)
        }

        for scheme in schemes {
            args.append("--schemes")
            args.append(scheme)
        }

        if retainPublic {
            args.append("--retain-public")
        }

        if skipBuild {
            args.append("--skip-build")
        }

        for target in excludeTargets {
            args.append("--exclude-targets")
            args.append(target)
        }

        for glob in reportExclude {
            args.append("--report-exclude")
            args.append(glob)
        }

        do {
            let result = try await ProcessResult.run(
                executablePath, arguments: args, mergeStderr: false,
                timeout: .seconds(600),
            )

            let declarations = Self.parseJSONOutput(result.stdout)

            if declarations.isEmpty {
                return CallTool.Result(content: [.text("No unused code found.")])
            }

            let message = Self.formatResults(declarations)
            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }

    struct UnusedDeclaration {
        let name: String
        let kind: String
        let hints: [String]
        let accessibility: String
        let file: String
        let line: Int
        let column: Int
    }

    static func parseJSONOutput(_ output: String) -> [UnusedDeclaration] {
        guard let data = output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        return array.compactMap { dict -> UnusedDeclaration? in
            guard let name = dict["name"] as? String,
                  let kind = dict["kind"] as? String,
                  let hints = dict["hints"] as? [String],
                  let location = dict["location"] as? String
            else {
                return nil
            }

            let accessibility = dict["accessibility"] as? String ?? "internal"
            let (file, line, column) = Self.parseLocation(location)

            return UnusedDeclaration(
                name: name, kind: kind, hints: hints,
                accessibility: accessibility, file: file, line: line, column: column,
            )
        }
    }

    static func parseLocation(_ location: String) -> (file: String, line: Int, column: Int) {
        // Format: "/path/to/file.swift:12:6"
        // Split from the right to handle paths that might contain colons
        let parts = location.split(separator: ":")
        guard parts.count >= 3,
              let line = Int(parts[parts.count - 2]),
              let column = Int(parts[parts.count - 1])
        else {
            return (location, 0, 0)
        }
        let file = parts[0 ..< parts.count - 2].joined(separator: ":")
        return (file, line, column)
    }

    static func formatResults(_ declarations: [UnusedDeclaration]) -> String {
        let grouped = Dictionary(grouping: declarations) { $0.file }
        let sortedFiles = grouped.keys.sorted()

        var lines = ["\(declarations.count) unused declaration(s) found:\n"]

        for file in sortedFiles {
            guard let fileDeclarations = grouped[file] else { continue }
            lines.append(file)
            for d in fileDeclarations {
                let hintsStr = d.hints.joined(separator: ", ")
                let kindLabel = Self.formatKind(d.kind)
                lines.append(
                    "  \(d.line):\(d.column) \(kindLabel) \(d.name) [\(hintsStr)] (\(d.accessibility))",
                )
            }
        }

        return lines.joined(separator: "\n")
    }

    static func formatKind(_ kind: String) -> String {
        switch kind {
            case "function.free": return "func"
            case "function.method.instance": return "method"
            case "function.method.static": return "static method"
            case "function.method.class": return "class method"
            case "var.instance": return "property"
            case "var.static": return "static property"
            case "var.global": return "var"
            case "enumelement": return "case"
            case "typealias": return "typealias"
            case "import": return "import"
            default: return kind
        }
    }
}
