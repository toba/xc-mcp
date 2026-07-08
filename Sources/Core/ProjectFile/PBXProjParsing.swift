import Foundation

/// Shared primitives for the text-level `project.pbxproj` parsers in this directory
/// (``PBXProjTextEditor``, ``PBXTargetMap``, ``PBXProjReferenceAudit``).
///
/// These consolidate three concerns that were previously reimplemented per file: locating and
/// decoding the pbxproj text, splitting it into lines, and recognizing a 24-character Xcode object
/// identifier.
public enum PBXProjParsing {
    /// The absolute path of the `project.pbxproj` inside a `.xcodeproj` bundle.
    public static func pbxprojPath(forProject projectPath: String) -> String {
        "\(projectPath)/project.pbxproj"
    }

    /// Decode `project.pbxproj` as UTF-8 text, or `nil` if the file is missing or not valid UTF-8.
    ///
    /// Callers that need to distinguish those failures (e.g. to throw a typed error) should read
    /// the bytes themselves; this is the "give up and fall back" convenience used by the read-only
    /// parsers.
    public static func readText(projectPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: pbxprojPath(forProject: projectPath))
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// The length in characters (and UTF-8 bytes) of an Xcode object identifier.
public extension PBXProjParsing {
    /// The fixed width of every pbxproj object identifier: 24 hexadecimal characters.
    static let identifierLength = 24

    /// Whether `token` is exactly a 24-character Xcode object identifier.
    ///
    /// - Parameter requireUppercase: When `true`, lowercase hex digits are rejected. Xcode always
    ///   emits uppercase identifiers, so parsers matching against on-disk IDs pass `true`; the
    ///   dangling-reference audit passes `false` to accept any well-formed token.
    static func isIdentifier(
        _ token: some StringProtocol,
        requireUppercase: Bool = false,
    ) -> Bool {
        let utf8 = token.utf8
        guard utf8.count == identifierLength else { return false }
        return utf8.allSatisfy { isHexByte($0, requireUppercase: requireUppercase) }
    }

    /// Whether `byte` is an ASCII hexadecimal digit (`0-9`, `A-F`, and — unless `requireUppercase`
    /// — `a-f`).
    static func isHexByte(_ byte: UInt8, requireUppercase: Bool = false) -> Bool {
        switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "A")...UInt8(ascii: "F"): true
            case UInt8(ascii: "a")...UInt8(ascii: "f"): !requireUppercase
            default: false
        }
    }
}

extension String {
    /// Split on newlines, preserving empty lines so line indices round-trip through a `joined`.
    func splitLines() -> [String] {
        split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
