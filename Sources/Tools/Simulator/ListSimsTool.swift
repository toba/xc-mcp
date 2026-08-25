import MCP
import XCMCPCore
import Foundation

public struct ListSimsTool: Sendable {
    private let simctlRunner: SimctlRunner

    public init(simctlRunner: SimctlRunner = .init()) { self.simctlRunner = simctlRunner }

    public func tool() -> Tool {
        .init(
            name: "list_sims",
            description:
                "List all available iOS/tvOS/watchOS simulators with their UDIDs, names, states, and runtimes.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "available_only": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, only show available (non-unavailable) simulators. Defaults to true.",
                        ),
                    ]),
                    "booted_only": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, only show booted simulators. Defaults to false.",
                        ),
                    ]),
                    "runtime_filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter by runtime (e.g., 'iOS', 'tvOS', 'watchOS'). Case-insensitive partial match.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let availableOnly = arguments.getBool("available_only", default: true)

        let bootedOnly = arguments.getBool("booted_only")

        let runtimeFilter = arguments.getString("runtime_filter")?.lowercased()

        do {
            var devices = try await simctlRunner.listDevices()

            // Apply filters
            if availableOnly { devices = devices.filter(\.isAvailable) }

            if bootedOnly { devices = devices.filter { $0.state == "Booted" } }

            if let filter = runtimeFilter {
                devices = devices.filter { $0.runtime?.lowercased().contains(filter) ?? false }
            }

            // Sort by runtime, then by name
            devices.sort { lhs, rhs in
                lhs.runtime != rhs.runtime
                    ? (lhs.runtime ?? "") < (rhs.runtime ?? "")
                    : lhs.name < rhs.name
            }

            // Format output
            if devices.isEmpty {
                return CallTool.Result.text("No simulators found matching the specified criteria.")
            }

            var output = "Found \(devices.count) simulator(s):\n\n"

            var currentRuntime = ""

            for device in devices {
                let runtime = device.runtime ?? "Unknown Runtime"

                if runtime != currentRuntime {
                    currentRuntime = runtime
                    output += "## \(formatRuntime(runtime))\n"
                }

                let stateIcon = device.state == "Booted" ? "🟢" : "⚪️"
                output += "  \(stateIcon) \(device.name)\n"
                output += "     UDID: \(device.udid)\n"
                output += "     State: \(device.state)\n"
            }

            return CallTool.Result.text(output)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Matches the platform and version of a runtime identifier
    private static nonisolated(unsafe) let runtimePattern = /SimRuntime\.([a-zA-Z]+)-(\d+)-(\d+)/

    private func formatRuntime(_ runtime: String) -> String {
        // Convert "com.apple.CoreSimulator.SimRuntime.iOS-17-0" to "iOS 17.0"
        guard let match = runtime.firstMatch(of: Self.runtimePattern) else { return runtime }
        return "\(match.1) \(match.2).\(match.3)"
    }
}
