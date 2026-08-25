import Darwin

/// Reads how much CPU time a process group has consumed.
///
/// The settle watchdog uses it to tell a child that is still working from one that finished its
/// work and stopped exiting. Output arrival cannot tell the two apart. A test binary writes through
/// a pipe, its stdio buffer is one 16 KB block, and a slow suite can run for minutes between two
/// writes. A run that is still executing burns CPU the whole time. (b5f682b1)
enum ProcessGroupActivity {
    /// The largest group this reads. A `swift test` run holds a driver, a build system and the test
    /// binary, so the real count stays far below it.
    private static let pidLimit = 256

    /// Sums the user and system CPU time of every live process in the group.
    ///
    /// - Parameter pgid: The pid of the process group leader.
    /// - Returns: The summed CPU time, or `nil` when the group holds no live process.
    static func cpuTime(ofGroup pgid: pid_t) -> Duration? {
        guard pgid > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: pidLimit)
        let byteCount = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(
                UInt32(PROC_PGRP_ONLY), UInt32(pgid), buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.size),
            )
        }
        guard byteCount > 0 else { return nil }

        let count = min(Int(byteCount) / MemoryLayout<pid_t>.size, pidLimit)
        var total: UInt64 = 0
        var foundOne = false

        for pid in pids[0..<count] where pid > 0 {
            guard let nanoseconds = cpuNanoseconds(ofProcess: pid) else { continue }
            total += nanoseconds
            foundOne = true
        }
        guard foundOne else { return nil }
        return .nanoseconds(total)
    }

    /// The user plus system CPU time of one process, in nanoseconds.
    ///
    /// - Returns: The time, or `nil` when the process is gone or refuses the query.
    private static func cpuNanoseconds(ofProcess pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard status == 0 else { return nil }
        return info.ri_user_time + info.ri_system_time
    }
}
