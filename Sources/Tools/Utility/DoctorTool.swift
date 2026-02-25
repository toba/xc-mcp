import MCP
import XCMCPCore
import Foundation

public struct DoctorTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "doctor",
            description:
            "Diagnose the Xcode development environment. Checks Xcode installation, command line tools, simulators, LLDB, SDKs, session state, and other dependencies.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments _: [String: Value]) async -> CallTool.Result {
        var diagnostics: [String] = []
        diagnostics.append("=== Xcode MCP Doctor ===\n")

        // Check macOS version
        diagnostics.append("## System Information")
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        diagnostics.append("macOS: \(osVersion)")
        diagnostics.append("Server version: 1.0.0")

        // Run all checks in parallel for faster execution
        async let xcodeCheck = checkXcode()
        async let cltCheck = checkCommandLineTools()
        async let xcodebuildCheck = checkXcodebuild()
        async let simctlCheck = checkSimctl()
        async let devicectlCheck = checkDevicectl()
        async let swiftCheck = checkSwift()
        async let lldbCheck = checkLLDB()
        async let sdksCheck = checkSDKs()
        async let derivedDataCheck = checkDerivedData()

        // Session state (requires await on actor)
        let sessionSummary = await sessionManager.summary()
        diagnostics.append("\n## Session State")
        diagnostics.append(sessionSummary)

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

        let lldb = await lldbCheck
        diagnostics.append("\n## LLDB")
        diagnostics.append(contentsOf: lldb)

        let sdks = await sdksCheck
        diagnostics.append("\n## SDKs")
        diagnostics.append(contentsOf: sdks)

        // Active debug sessions
        let debugSessions = await LLDBSessionManager.shared.getAllSessions()
        diagnostics.append("\n## Active Debug Sessions")
        if debugSessions.isEmpty {
            diagnostics.append("No active debug sessions")
        } else {
            for (bundleId, pid) in debugSessions {
                diagnostics.append("  \(bundleId): PID \(pid)")
            }
        }

        let derivedData = await derivedDataCheck
        diagnostics.append("\n## DerivedData")
        diagnostics.append(contentsOf: derivedData)

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
                "[WARN] Some checks failed. Review the issues above and fix them before proceeding.",
            )
        }

        return CallTool.Result(
            content: [
                .text(diagnostics.joined(separator: "\n")),
            ],
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
                "/usr/bin/xcodebuild", arguments: ["-version"],
            )
            if versionResult.exitCode == 0 {
                let version =
                    versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: .newlines).first ?? "Unknown"
                results.append("[OK] \(version)")
            }
        } else {
            results.append(
                "[FAIL] Xcode not found. Install Xcode from the App Store or run: xcode-select --install",
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
                    "[FAIL] Command Line Tools not found. Run: xcode-select --install",
                )
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
                "/usr/bin/xcodebuild", arguments: ["-checkFirstLaunchStatus"],
            )
            if licenseCheck.exitCode == 0 {
                results.append("[OK] Xcode license accepted")
            } else if licenseCheck.stderr.contains("license") {
                results.append(
                    "[FAIL] Xcode license not accepted. Run: sudo xcodebuild -license accept",
                )
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
                "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"],
            )
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
                "[WARN] devicectl not available (requires Xcode 15+, only needed for physical device support)",
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
                    separatedBy: .newlines,
                ).first ?? "Unknown"
            results.append("[OK] \(version)")
        } else {
            results.append("[FAIL] Swift not found")
        }

        return results
    }

    private func checkLLDB() async -> [String] {
        var results: [String] = []

        let result = await runCommand("/usr/bin/xcrun", arguments: ["lldb", "--version"])
        if result.exitCode == 0 {
            let version =
                result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines).first ?? "Unknown"
            results.append("[OK] \(version)")
        } else {
            results.append("[WARN] LLDB not available")
        }

        return results
    }

    private func checkSDKs() async -> [String] {
        var results: [String] = []

        let result = await runCommand("/usr/bin/xcodebuild", arguments: ["-showsdks"])
        if result.exitCode == 0 {
            let lines = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .filter { $0.contains("-sdk ") }
            if lines.isEmpty {
                results.append("[WARN] No SDKs found")
            } else {
                for line in lines {
                    results.append("  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        } else {
            results.append("[WARN] Could not list SDKs")
        }

        return results
    }

    private func checkDerivedData() -> [String] {
        var results: [String] = []

        let derivedDataPath = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        let fm = FileManager.default

        if fm.fileExists(atPath: derivedDataPath) {
            do {
                let attrs = try fm.attributesOfFileSystem(forPath: derivedDataPath)
                if let freeSize = attrs[.systemFreeSize] as? Int64 {
                    let freeGB = Double(freeSize) / 1_073_741_824
                    results.append(
                        String(format: "Disk free space: %.1f GB", freeGB),
                    )
                }
                // Count subdirectories to estimate project count
                let contents = try fm.contentsOfDirectory(atPath: derivedDataPath)
                let projectDirs = contents.filter { !$0.hasPrefix(".") }
                results.append("Cached projects: \(projectDirs.count)")
            } catch {
                results.append("[WARN] Could not read DerivedData: \(error.localizedDescription)")
            }
        } else {
            results.append("DerivedData directory does not exist (clean state)")
        }

        return results
    }

    private func runCommand(_ command: String, arguments: [String]) async -> (
        exitCode: Int32, stdout: String, stderr: String,
    ) {
        do {
            let result = try await ProcessResult.run(
                command, arguments: arguments, mergeStderr: false,
            )
            return (result.exitCode, result.stdout, result.stderr)
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}
