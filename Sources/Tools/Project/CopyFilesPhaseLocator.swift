import MCP
import XcodeProj

/// Shared logic for locating a build phase on a target
///
/// Priority in both entry points: explicit `phaseName` → `dstPath` (on Copy Files phases) → the
/// target's sole Copy Files phase. The add and remove tools locate the same phase from the same
/// arguments because they both come through here.
enum CopyFilesPhaseLocator {
    /// Locates a Copy Files phase, matching `phaseName` against Copy Files phases alone.
    ///
    /// - Parameters:
    ///   - target: The target to search.
    ///   - phaseName: The phase name the caller passed, or `nil`.
    ///   - dstPath: The destination path the caller passed, or `nil`.
    ///   - targetName: The target name, used in the error text.
    /// - Throws: ``MCPError/invalidParams(_:)`` when nothing matches, or when the arguments leave
    ///   more than one candidate.
    static func locate(
        in target: PBXNativeTarget,
        phaseName: String?,
        dstPath: String?,
        targetName: String,
    ) throws(MCPError) -> PBXCopyFilesBuildPhase {
        let copyPhases = copyPhases(of: target)

        if let phaseName {
            let matches = copyPhases.filter { $0.name == phaseName }

            switch matches.count {
                case 0:
                    throw .invalidParams(
                        "Copy Files phase '\(phaseName)' not found on target '\(targetName)'",
                    )
                case 1: return matches[0]
                default:
                    throw .invalidParams(
                        "Multiple Copy Files phases on target '\(targetName)' are named '\(phaseName)' — pass dst_path to disambiguate",
                    )
            }
        }

        if let dstPath {
            return try copyPhase(in: target, dstPath: dstPath, targetName: targetName)
        }
        return try soleCopyPhase(in: target, targetName: targetName)
    }

    /// Locates any build phase, matching `phaseName` against every phase type.
    ///
    /// The synchronized-folder tools take this entry point, because a folder exception can name a
    /// Sources or Resources phase as readily as a Copy Files one.
    ///
    /// - Parameters:
    ///   - target: The target to search.
    ///   - phaseName: The phase name the caller passed, or `nil`.
    ///   - dstPath: The destination path the caller passed, or `nil`.
    ///   - targetName: The target name, used in the error text.
    /// - Throws: ``MCPError/invalidParams(_:)`` when nothing matches, or when the arguments leave
    ///   more than one candidate.
    static func locateAnyPhase(
        in target: PBXNativeTarget,
        phaseName: String?,
        dstPath: String?,
        targetName: String,
    ) throws(MCPError) -> PBXBuildPhase {
        if let phaseName {
            guard let byName = target.buildPhases.first(where: { $0.name() == phaseName }) else {
                throw .invalidParams(
                    "Build phase named '\(phaseName)' not found on target '\(targetName)'",
                )
            }
            return byName
        }

        if let dstPath {
            return try copyPhase(in: target, dstPath: dstPath, targetName: targetName)
        }
        return try soleCopyPhase(
            in: target,
            targetName: targetName,
            emptyHint: " Pass phase_name to select a different phase type.",
        )
    }

    private static func copyPhases(of target: PBXNativeTarget) -> [PBXCopyFilesBuildPhase] {
        target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
    }

    /// The one Copy Files phase whose destination is `dstPath`.
    private static func copyPhase(
        in target: PBXNativeTarget,
        dstPath: String,
        targetName: String,
    ) throws(MCPError) -> PBXCopyFilesBuildPhase {
        let matches = copyPhases(of: target).filter { ($0.dstPath ?? "") == dstPath }

        switch matches.count {
            case 0:
                throw .invalidParams(
                    "No Copy Files phase with dstPath '\(dstPath)' on target '\(targetName)'",
                )
            case 1: return matches[0]
            default:
                throw .invalidParams(
                    "Multiple Copy Files phases on target '\(targetName)' have dstPath '\(dstPath)' — pass phase_name to disambiguate",
                )
        }
    }

    /// The target's only Copy Files phase, for a caller that named neither a phase nor a
    /// destination.
    ///
    /// - Parameter emptyHint: A sentence appended when the target carries no Copy Files phase.
    private static func soleCopyPhase(
        in target: PBXNativeTarget,
        targetName: String,
        emptyHint: String = "",
    ) throws(MCPError) -> PBXCopyFilesBuildPhase {
        let copyPhases = copyPhases(of: target)

        switch copyPhases.count {
            case 0:
                throw .invalidParams(
                    "Target '\(targetName)' has no Copy Files build phases\(emptyHint)",
                )
            case 1: return copyPhases[0]
            default:
                let names = copyPhases.map { $0.name ?? ("dstPath=" + ($0.dstPath ?? "")) }
                throw .invalidParams(
                    "Target '\(targetName)' has \(copyPhases.count) Copy Files phases: \(names.joined(separator: ", ")). Pass phase_name or dst_path to disambiguate.",
                )
        }
    }
}
