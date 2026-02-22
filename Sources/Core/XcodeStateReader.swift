import System
import Foundation
import Subprocess

/// Result of reading Xcode IDE state from UserInterfaceState.xcuserstate.
public struct XcodeStateResult: Sendable {
    public let scheme: String?
    public let simulatorUDID: String?
    public let simulatorName: String?
    public let error: String?

    public init(
        scheme: String? = nil,
        simulatorUDID: String? = nil,
        simulatorName: String? = nil,
        error: String? = nil,
    ) {
        self.scheme = scheme
        self.simulatorUDID = simulatorUDID
        self.simulatorName = simulatorName
        self.error = error
    }
}

/// Reads the active scheme and run destination from Xcode's UserInterfaceState.xcuserstate.
public enum XcodeStateReader {
    /// Reads Xcode IDE state for the given project or workspace path.
    ///
    /// Finds the xcuserstate file, converts it from binary plist via plutil,
    /// then parses the NSKeyedArchiver objects to extract scheme and destination.
    ///
    /// - Parameter path: Path to .xcodeproj or .xcworkspace.
    /// - Returns: Parsed state or an error description.
    public static func readState(projectOrWorkspacePath path: String) async -> XcodeStateResult {
        let username = NSUserName()
        let candidates = xcuserstateCandidates(for: path, username: username)

        guard
            let statePath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else {
            return XcodeStateResult(
                error:
                "No UserInterfaceState.xcuserstate found for user '\(username)'. Tried:\n\(candidates.joined(separator: "\n"))",
            )
        }

        // Convert binary plist to XML via plutil
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcuserstate_\(ProcessInfo.processInfo.processIdentifier).xml")
        let tempPath = tempURL.path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let convertResult = await runProcess(
            "/usr/bin/plutil",
            arguments: ["-convert", "xml1", "-o", tempPath, statePath],
        )
        guard convertResult.exitCode == 0 else {
            return XcodeStateResult(
                error: "plutil conversion failed: \(convertResult.stderr)",
            )
        }

        // Parse the XML plist
        guard let data = FileManager.default.contents(atPath: tempPath) else {
            return XcodeStateResult(error: "Failed to read converted plist")
        }

        do {
            guard
                let plist = try PropertyListSerialization.propertyList(
                    from: data, format: nil,
                ) as? [String: Any],
                let objects = plist["$objects"] as? [Any]
            else {
                return XcodeStateResult(error: "Unexpected plist structure (not NSKeyedArchiver)")
            }

            return extractState(from: objects)
        } catch {
            return XcodeStateResult(error: "Plist parse error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private static func xcuserstateCandidates(for path: String, username: String) -> [String] {
        var candidates: [String] = []

        if path.hasSuffix(".xcworkspace") {
            // Workspace-level state
            candidates.append(
                "\(path)/xcuserdata/\(username).xcuserdatad/UserInterfaceState.xcuserstate",
            )
        } else if path.hasSuffix(".xcodeproj") {
            // Project workspace state
            candidates.append(
                "\(path)/project.xcworkspace/xcuserdata/\(username).xcuserdatad/UserInterfaceState.xcuserstate",
            )
            // Also check project-level xcuserdata
            candidates.append(
                "\(path)/xcuserdata/\(username).xcuserdatad/UserInterfaceState.xcuserstate",
            )
        }

        return candidates
    }

    /// Extracts scheme and destination from NSKeyedArchiver $objects array.
    private static func extractState(from objects: [Any]) -> XcodeStateResult {
        var scheme: String?
        var simulatorUDID: String?
        var simulatorName: String?

        // Look for scheme name: find "IDENamedSchemeReference" class then get its scheme name
        for (index, obj) in objects.enumerated() {
            guard let dict = obj as? [String: Any] else { continue }

            // Check for scheme reference class
            if let className = resolveString(dict["$class"], in: objects),
               className.contains("SchemeReference") || className.contains("IDERunContextState")
            {
                // Look for a string key that holds the scheme name
                if let nameRef = dict["schemeName"], let name = resolveString(nameRef, in: objects),
                   !name.isEmpty
                {
                    scheme = name
                }
                if let nameRef = dict["name"], let name = resolveString(nameRef, in: objects),
                   !name.isEmpty, scheme == nil
                {
                    scheme = name
                }
            }

            // Look for run destination with UDID
            if let className = resolveString(dict["$class"], in: objects),
               className.contains("RunDestination") || className.contains("DeviceState")
            {
                if let udidRef = dict["deviceIdentifier"],
                   let udid = resolveString(udidRef, in: objects),
                   isUDID(udid)
                {
                    simulatorUDID = udid
                }
                if let nameRef = dict["name"], let name = resolveString(nameRef, in: objects),
                   !name.isEmpty
                {
                    simulatorName = name
                }
            }

            // Fallback: scan all strings for UDID patterns near "Simulator" context
            if let str = obj as? String, isUDID(str), simulatorUDID == nil {
                // Check if nearby objects mention simulator
                let nearbyRange =
                    max(0, index - 5) ..< min(objects.count, index + 5)
                for nearby in nearbyRange {
                    if let nearStr = objects[nearby] as? String,
                       nearStr.lowercased().contains("simulator")
                    {
                        simulatorUDID = str
                        break
                    }
                }
            }
        }

        if scheme == nil, simulatorUDID == nil {
            return XcodeStateResult(
                error:
                "Could not find scheme or destination in Xcode state. The project may not have been opened in Xcode recently.",
            )
        }

        return XcodeStateResult(
            scheme: scheme, simulatorUDID: simulatorUDID, simulatorName: simulatorName,
        )
    }

    /// Resolves a plist value that may be a UID reference into the $objects array.
    private static func resolveString(_ value: Any?, in objects: [Any]) -> String? {
        if let str = value as? String {
            return str
        }
        // NSKeyedArchiver uses CF$UID references
        if let dict = value as? [String: Any], let uid = dict["CF$UID"] as? Int,
           uid < objects.count
        {
            return objects[uid] as? String
        }
        return nil
    }

    private static func isUDID(_ string: String) -> Bool {
        // UDIDs are typically uppercase hex with dashes: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
        let pattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
        return string.range(of: pattern, options: .regularExpression) != nil
    }

    private static func runProcess(_ path: String, arguments: [String]) async -> (
        exitCode: Int32, stdout: String, stderr: String,
    ) {
        do {
            let result = try await ProcessResult.runSubprocess(
                .path(FilePath(path)),
                arguments: Arguments(arguments),
            )
            return (result.exitCode, result.stdout, result.stderr)
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }
}
