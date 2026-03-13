import Foundation

/// Parses a `.pbxproj` file to build a mapping of target UUIDs to target names.
///
/// This avoids depending on XcodeProj for lightweight cases where only
/// the UUID↔name mapping is needed (e.g. xcbaseline file management).
public enum PBXTargetMap {
    /// Returns a dictionary mapping 24-character target UUIDs to their display names.
    ///
    /// Parses `PBXNativeTarget` blocks in the pbxproj, handling both formats:
    /// - UUID and `isa` on the same line
    /// - UUID on the line preceding `isa = PBXNativeTarget`
    public static func buildMap(projectPath: String) -> [String: String] {
        let pbxprojPath = "\(projectPath)/project.pbxproj"
        guard let data = FileManager.default.contents(atPath: pbxprojPath),
              let content = String(data: data, encoding: .utf8)
        else {
            return [:]
        }

        var map = [String: String]()
        var inTarget = false
        var currentUUID: String?
        var pendingUUID: String?

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

            // Track UUID from block-opening lines like: UUID /* Name */ = {
            if let uuid = extractLeadingUUID(trimmed) {
                pendingUUID = uuid
            }

            if trimmed.contains("isa = PBXNativeTarget") {
                inTarget = true
                // UUID may be on this line or the previous line
                currentUUID = extractLeadingUUID(trimmed) ?? pendingUUID
            }

            if inTarget, trimmed.hasPrefix("name = ") {
                let name = trimmed
                    .dropFirst("name = ".count)
                    .replacingOccurrences(of: ";", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")

                if let uuid = currentUUID {
                    map[uuid] = name
                }
                inTarget = false
                currentUUID = nil
            }

            if inTarget, trimmed == "};" {
                inTarget = false
                currentUUID = nil
            }
        }

        return map
    }

    /// Looks up a single target UUID by name, with a fallback scan for comment references.
    ///
    /// Returns the UUID string or nil if not found.
    public static func findUUID(
        projectPath: String, targetName: String,
    ) -> String? {
        let map = buildMap(projectPath: projectPath)

        // Direct lookup (name → UUID)
        for (uuid, name) in map where name == targetName {
            return uuid
        }

        // Fallback: scan for /* TargetName */ comment references
        let pbxprojPath = "\(projectPath)/project.pbxproj"
        guard let data = FileManager.default.contents(atPath: pbxprojPath),
              let content = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains("PBXNativeTarget") { continue }
            if line.contains("/* \(targetName) */"),
               let range = line.range(of: #"[A-F0-9]{24}"#, options: .regularExpression)
            {
                return String(line[range])
            }
        }

        return nil
    }

    // MARK: - Private

    private static func extractLeadingUUID(_ line: some StringProtocol) -> String? {
        guard line.count >= 24 else { return nil }
        let prefix = line.prefix(24)
        // Check all characters are uppercase hex
        guard prefix.allSatisfy({ $0.isHexDigit && ($0.isUppercase || $0.isNumber) }) else {
            return nil
        }
        return String(prefix)
    }
}
