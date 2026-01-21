import Foundation
import XCMCPCore
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

    public func execute(arguments: [String: Value]) async -> CallTool.Result {
        var diagnostics: [String] = []
        diagnostics.append("=== Xcode MCP Doctor ===\n")

        // Check macOS version
        diagnostics.append("## System Information")
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        diagnostics.append("macOS: \(osVersion)")

        // Run all checks in parallel for faster execution
        async let xcodeCheck = checkXcode()
        async let cltCheck = checkCommandLineTools()
        async let xcodebuildCheck = checkXcodebuild()
        async let simctlCheck = checkSimctl()
        async let devicectlCheck = checkDevicectl()
        async let swiftCheck = checkSwift()

        // Await results and append in order
        let xcode = await xcodeCheck
        diagnostics.append("\n## Xcode")
        diagnostics.append(contentsOf: xcode)

        let clt = await cltCheck
        diagnostics.append("\n## Command Line Tools")
        diagnostics.append(contentsOf: clt)

        let xcodebuild = await xcodebuildCheck
        diagnostics.append("\n## xcodebuild")
        diagnostics.append(contentsOf: xcodebuild)

        let simctl = await simctlCheck
        diagnostics.append("\n## Simulator")
        diagnostics.append(contentsOf: simctl)

        let devicectl = await devicectlCheck
        diagnostics.append("\n## Device Control")
        diagnostics.append(contentsOf: devicectl)

        let swift = await swiftCheck
        diagnostics.append("\n## Swift")
        diagnostics.append(contentsOf: swift)

        // Summary
        diagnostics.append("\n## Summary")
        let allPassed =
            xcode.allSatisfy { !$0.contains("[FAIL]") }
            && clt.allSatisfy { !$0.contains("[FAIL]") }
            && xcodebuild.allSatisfy { !$0.contains("[FAIL]") }
            && simctl.allSatisfy { !$0.contains("[FAIL]") }
            && swift.allSatisfy { !$0.contains("[FAIL]") }

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

    private func checkCommandLineTools() -> [String] {
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

    private func runCommand(_ command: String, arguments: [String]) -> (
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
