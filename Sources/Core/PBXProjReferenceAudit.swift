import Foundation

/// Audits a serialized `project.pbxproj` for **dangling object references** — UUID-shaped tokens
/// that do not resolve to an entry in the `objects` table.
///
/// A synchronized-folder exception set, a `TargetAttributes` entry, or a target dependency left
/// pointing at a deleted object is exactly the corruption that makes Xcode fail to load a project
/// (and that has trapped XcodeProj's serializer in the past). `plutil -lint` cannot catch it — the
/// file is still a *valid plist*, just an internally-inconsistent one. This audit is the universal
/// net wired into ``SafeProjectWrite`` so no mutation tool can durably write a project whose object
/// graph references something that no longer exists.
public enum PBXProjReferenceAudit {
    /// Whether `path` is an Xcode project object graph this audit understands.
    public static func isProjectFile(_ path: String) -> Bool { path.hasSuffix("project.pbxproj") }

    /// Every UUID-shaped token in `data` that is **not** a key of the `objects` table. Returns an
    /// empty set when the data cannot be parsed as a pbxproj — validating the plist *shape* is
    /// `plutil`'s job, so the audit fails open rather than blocking on a parse it doesn't own.
    public static func danglingReferences(in data: Data) -> Set<String> {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
            let root = plist as? [String: Any],
            let objects = root["objects"] as? [String: Any]
        else { return [] }

        let defined = Set(objects.keys)
        var referenced = Set<String>()
        collectReferences(in: root, into: &referenced)
        return referenced.subtracting(defined)
    }

    /// Dangling references present in `candidate` but **not already present** in `baseline`.
    ///
    /// The gate only refuses writes that *introduce* a dangling reference — never one that already
    /// existed on disk — so an already-broken project (e.g. one a prior buggy write corrupted) can
    /// still be repaired rather than wedging every future write of it.
    public static func newDanglingReferences(candidate: Data, baseline: Data?) -> Set<String> {
        let existing = baseline.map(danglingReferences(in:)) ?? []
        return danglingReferences(in: candidate).subtracting(existing)
    }

    // MARK: - Private

    /// The pbxproj field whose value identifies an object in a *different* project file.
    private static let crossProjectReferenceKey = "remoteGlobalIDString"

    /// A 24-character hexadecimal token — the exact shape of every Xcode object identifier.
    /// Build-setting values of this precise shape do not occur in practice, so matching is
    /// reference-precise (the `newDanglingReferences` baseline diff absorbs any rare exception).
    private static func isReferenceToken(_ string: String) -> Bool {
        string.utf8.count == 24 && string.utf8.allSatisfy(isHexByte)
    }

    private static func isHexByte(_ byte: UInt8) -> Bool {
        switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "a")...UInt8(ascii: "f"),
                 UInt8(ascii: "A")...UInt8(ascii: "F"):
                true
            default:
                false
        }
    }

    private static func collectReferences(in value: Any, into out: inout Set<String>) {
        switch value {
            case let dict as [String: Any]:
                for (key, nested) in dict {
                    // Keys can themselves be references (e.g. `TargetAttributes` is keyed by the
                    // target's UUID), so a deleted target leaves a dangling key, not just a value.
                    if isReferenceToken(key) { out.insert(key) }
                    // `remoteGlobalIDString` is the one field that legitimately holds an identifier
                    // living in ANOTHER project's object graph (a cross-project dependency, paired
                    // with `containerPortal`). It is never an in-file reference, so excluding it
                    // avoids false-positiving every cross-project dependency.
                    if key == Self.crossProjectReferenceKey { continue }
                    collectReferences(in: nested, into: &out)
                }
            case let array as [Any]:
                for element in array { collectReferences(in: element, into: &out) }
            case let string as String:
                if isReferenceToken(string) { out.insert(string) }
            default:
                break
        }
    }
}
