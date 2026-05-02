import MCP
import XCMCPCore
import Foundation

public struct StartMacLogCapTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "start_mac_log_cap",
            description:
            "Start capturing logs from a macOS app using the unified logging system. Logs are written to a file and can be stopped with stop_mac_log_cap.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional bundle identifier to filter logs to a specific app. Uses the last component as the executable name (e.g., 'com.example.MyApp' matches process 'MyApp').",
                        ),
                    ]),
                    "process_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional process name to filter logs to a specific process.",
                        ),
                    ]),
                    "subsystem": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional OSLog subsystem to filter logs (e.g., 'com.apple.CloudKit').",
                        ),
                    ]),
                    "predicate": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional custom predicate to filter logs. Overrides bundle_id, process_name, and subsystem filters.",
                        ),
                    ]),
                    "level": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Log level to capture: 'default', 'info', or 'debug'. Default is 'default' which excludes info/debug messages. Use 'info' or 'debug' to capture lower-severity messages.",
                        ),
                        "enum": .array([
                            .string("default"),
                            .string("info"),
                            .string("debug"),
                        ]),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to write logs to. Defaults to /tmp/mac_log_<identifier>.log",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleId = arguments.getString("bundle_id")
        let processName = arguments.getString("process_name")
        let subsystem = arguments.getString("subsystem")
        let customPredicate = arguments.getString("predicate")
        let level = arguments.getString("level")
        let outputFile =
            arguments.getString("output_file")
                ?? "/tmp/mac_log_\(bundleId ?? processName ?? "system").log"

        do {
            var args = ["stream", "--style", "compact"]

            // Add log level flags
            if let level {
                switch level {
                    case "debug":
                        args.append("--debug")
                    case "info":
                        args.append("--info")
                    default:
                        break // "default" needs no flag
                }
            }

            var predicate: String?

            if let customPredicate {
                predicate = customPredicate
            } else {
                var predicateParts: [String] = []

                if let bundleId {
                    // Resolve the actual executable name from the app bundle when
                    // possible, since the last component of the bundle ID may not
                    // match the binary name (e.g., "com.thesisapp.testapp" but
                    // the executable is "TestApp").
                    let appName: String
                    if let resolved = await Self.resolveExecutableName(bundleId: bundleId) {
                        appName = resolved
                        predicateParts.append("process == \"\(appName)\"")
                    } else {
                        appName = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
                        predicateParts.append("process ==[cd] \"\(appName)\"")
                    }
                }
                if let processName {
                    predicateParts.append("process == \"\(processName)\"")
                }
                if let subsystem {
                    predicateParts.append("subsystem == \"\(subsystem)\"")
                }

                if !predicateParts.isEmpty {
                    predicate = predicateParts.joined(separator: " AND ")
                }
            }

            if let predicate {
                args.append(contentsOf: ["--predicate", predicate])
            }

            let pid = try LogCapture.launchStreamProcess(
                executable: "/usr/bin/log", arguments: args, outputFile: outputFile,
            )

            // Verify the log stream process is still running after a brief delay
            try await LogCapture.verifyStreamHealth(pid: pid, outputFile: outputFile)

            var message = "Started macOS log capture\n"
            message += "Output file: \(outputFile)\n"
            message += "Process ID: \(pid)\n"
            if let predicate {
                message += "Predicate: \(predicate)\n"
            }
            if let level, level != "default" {
                message += "Level: \(level) (includes \(level) and above)\n"
            }
            message += "\nUse stop_mac_log_cap to stop the capture."

            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Resolves the actual executable name from an app bundle's Info.plist.
    /// Uses `mdfind` to locate the app by bundle ID, then reads CFBundleExecutable.
    static func resolveExecutableName(bundleId: String) async -> String? {
        guard
            let result = try? await ProcessResult.run(
                "/usr/bin/mdfind",
                arguments: ["kMDItemCFBundleIdentifier == '\(bundleId)'"],
                timeout: .seconds(5),
            ), result.succeeded
        else {
            return nil
        }

        guard
            let appPath = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first(where: { $0.hasSuffix(".app") }), !appPath.isEmpty
        else {
            return nil
        }

        let infoPlistURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil,
              ) as? [String: Any],
              let executable = plist["CFBundleExecutable"] as? String
        else {
            return nil
        }

        return executable
    }
}
