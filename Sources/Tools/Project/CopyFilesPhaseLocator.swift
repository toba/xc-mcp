import MCP
import XcodeProj

/// Shared logic for locating a `PBXCopyFilesBuildPhase` on a target.
///
/// Priority: explicit `phaseName` → `dstPath` (on Copy Files phases) →
/// the target's sole Copy Files phase.
enum CopyFilesPhaseLocator {
    static func locate(
        in target: PBXNativeTarget,
        phaseName: String?,
        dstPath: String?,
        targetName: String,
    ) throws -> PBXCopyFilesBuildPhase {
        let copyPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }

        if let phaseName {
            let matches = copyPhases.filter { $0.name == phaseName }
            switch matches.count {
                case 0:
                    throw MCPError.invalidParams(
                        "Copy Files phase '\(phaseName)' not found on target '\(targetName)'",
                    )
                case 1:
                    return matches[0]
                default:
                    throw MCPError.invalidParams(
                        "Multiple Copy Files phases on target '\(targetName)' are named '\(phaseName)' — pass dst_path to disambiguate",
                    )
            }
        }

        if let dstPath {
            let matches = copyPhases.filter { ($0.dstPath ?? "") == dstPath }
            switch matches.count {
                case 0:
                    throw MCPError.invalidParams(
                        "No Copy Files phase with dstPath '\(dstPath)' on target '\(targetName)'",
                    )
                case 1:
                    return matches[0]
                default:
                    throw MCPError.invalidParams(
                        "Multiple Copy Files phases on target '\(targetName)' have dstPath '\(dstPath)' — pass phase_name to disambiguate",
                    )
            }
        }

        switch copyPhases.count {
            case 0:
                throw MCPError.invalidParams(
                    "Target '\(targetName)' has no Copy Files build phases",
                )
            case 1:
                return copyPhases[0]
            default:
                let names = copyPhases.map { $0.name ?? ("dstPath=" + ($0.dstPath ?? "")) }
                throw MCPError.invalidParams(
                    "Target '\(targetName)' has \(copyPhases.count) Copy Files phases: \(names.joined(separator: ", ")). Pass phase_name or dst_path to disambiguate.",
                )
        }
    }
}
