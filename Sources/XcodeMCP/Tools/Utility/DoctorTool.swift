import Foundation
import MCP

public struct DoctorTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "doctor",
            description:
                "Diagnose the Xcode development environment. Checks Xcode installation, command line tools, simulators, and other dependencies.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var diagnostics: [String] = []
        diagnostics.append("=== Xcode MCP Doctor ===\n")

        // Check macOS version
        diagnostics.append("## System Information")
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        diagnostics.append("macOS: \(osVersion)")

        // Check Xcode installation
        diagnostics.append("\n## Xcode")
        let xcodeCheck = await checkXcode()
        diagnostics.append(contentsOf: xcodeCheck)

        // Check Command Line Tools
        diagnostics.append("\n## Command Line Tools")
        let cltCheck = await checkCommandLineTools()
        diagnostics.append(contentsOf: cltCheck)

        // Check xcodebuild
        diagnostics.append("\n## xcodebuild")
        let xcodebuildCheck = await checkXcodebuild()
        diagnostics.append(contentsOf: xcodebuildCheck)

        // Check simctl
        diagnostics.append("\n## Simulator")
        let simctlCheck = await checkSimctl()
        diagnostics.append(contentsOf: simctlCheck)

        // Check devicectl
        diagnostics.append("\n## Device Control")
        let devicectlCheck = await checkDevicectl()
        diagnostics.append(contentsOf: devicectlCheck)

        // Check Swift
        diagnostics.append("\n## Swift")
        let swiftCheck = await checkSwift()
        diagnostics.append(contentsOf: swiftCheck)

        // Summary
        diagnostics.append("\n## Summary")
        let allPassed =
            xcodeCheck.allSatisfy { !$0.contains("[FAIL]") }
            && cltCheck.allSatisfy { !$0.contains("[FAIL]") }
            && xcodebuildCheck.allSatisfy { !$0.contains("[FAIL]") }
            && simctlCheck.allSatisfy { !$0.contains("[FAIL]") }
            && swiftCheck.allSatisfy { !$0.contains("[FAIL]") }

        if allPassed {
            diagnostics.append("[OK] All checks passed. Your environment is ready for development.")
        } else {
            diagnostics.append(
                "[WARN] Some checks failed. Review the issues above and fix them before proceeding."
            )
        }

        return CallTool.Result(
            content: [.text(diagnostics.joined(separator: "\n"))]
        )
    }

    private func checkXcode() async -> [String] {
        var results: [String] = []

        // Check xcode-select path
        let selectResult = await runCommand("/usr/bin/xcode-select", arguments: ["-p"])
        if selectResult.exitCode == 0 {
            let path = selectResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            results.append("[OK] Xcode selected: \(path)")

            // Get Xcode version
            let versionResult = await runCommand(
                "/usr/bin/xcodebuild", arguments: ["-version"])
            if versionResult.exitCode == 0 {
                let version =
                    versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines).first ?? "Unknown"
                results.append("[OK] \(version)")
            }
        } else {
            results.append(
                "[FAIL] Xcode not found. Install Xcode from the App Store or run: xcode-select --install"
            )
        }

        return results
    }

    private func checkCommandLineTools() async -> [String] {
        var results: [String] = []

        let cltPath = "/Library/Developer/CommandLineTools"
        if FileManager.default.fileExists(atPath: cltPath) {
            results.append("[OK] Command Line Tools installed at \(cltPath)")
        } else {
            let xcodeDevPath = "/Applications/Xcode.app/Contents/Developer"
            if FileManager.default.fileExists(atPath: xcodeDevPath) {
                results.append("[OK] Using Xcode's built-in developer tools")
            } else {
                results.append(
                    "[FAIL] Command Line Tools not found. Run: xcode-select --install")
            }
        }

        return results
    }

    private func checkXcodebuild() async -> [String] {
        var results: [String] = []

        let result = await runCommand("/usr/bin/which", arguments: ["xcodebuild"])
        if result.exitCode == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            results.append("[OK] xcodebuild found: \(path)")

            // Check if license is accepted
            let licenseCheck = await runCommand(
                "/usr/bin/xcodebuild", arguments: ["-checkFirstLaunchStatus"])
            if licenseCheck.exitCode == 0 {
                results.append("[OK] Xcode license accepted")
            } else if licenseCheck.stderr.contains("license") {
                results.append(
                    "[FAIL] Xcode license not accepted. Run: sudo xcodebuild -license accept")
            }
        } else {
            results.append("[FAIL] xcodebuild not found")
        }

        return results
    }

    private func checkSimctl() async -> [String] {
        var results: [String] = []

        let result = await runCommand("/usr/bin/xcrun", arguments: ["simctl", "help"])
        if result.exitCode == 0 {
            results.append("[OK] simctl available")

            // Count available simulators
            let listResult = await runCommand(
                "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
            if listResult.exitCode == 0 {
                // Count devices from JSON
                let deviceCount =
                    listResult.stdout.components(separatedBy: "\"udid\"").count - 1
                results.append("[OK] \(max(0, deviceCount)) simulators available")
            }
        } else {
            results.append("[FAIL] simctl not available")
        }

        return results
    }

    private func checkDevicectl() async -> [String] {
        var results: [String] = []

        let result = await runCommand("/usr/bin/xcrun", arguments: ["devicectl", "version"])
        if result.exitCode == 0 {
            results.append("[OK] devicectl available")
        } else {
            results.append(
                "[WARN] devicectl not available (requires Xcode 15+, only needed for physical device support)"
            )
        }

        return results
    }

    private func checkSwift() async -> [String] {
        var results: [String] = []

        let result = await runCommand("/usr/bin/swift", arguments: ["--version"])
        if result.exitCode == 0 {
            let version =
                result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).components(
                    separatedBy: .newlines
                ).first ?? "Unknown"
            results.append("[OK] \(version)")
        } else {
            results.append("[FAIL] Swift not found")
        }

        return results
    }

    private func runCommand(_ command: String, arguments: [String]) async -> (
        exitCode: Int32, stdout: String, stderr: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return (
                process.terminationStatus,
                String(data: stdoutData, encoding: .utf8) ?? "",
                String(data: stderrData, encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}
