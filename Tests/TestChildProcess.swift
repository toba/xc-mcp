import Foundation
@testable import XCMCPCore

/// A child process a test spawns, wired so it can never wedge the test run.
///
/// `swift-test` reads the test binary's stdout pipe until every writer closes it. A child that
/// inherits file descriptor 1 and outlives the binary holds that pipe open, so `swift-test` sits in
/// `read` for as long as the child lives. A `sleep 300` left behind by one test costs the whole run
/// five minutes. Two guards close that hole:
///
/// - ``launch(_:_:)`` puts all three standard descriptors on the null device, so a survivor holds
///   nothing the test binary owns.
/// - ``terminateTree()`` kills the descendants a shell forked before it kills the shell, so a
///   survivor is unlikely in the first place.
///
/// A test that needs the child's output should keep using `ProcessResult.run` instead.
final class TestChildProcess {
    private let process: Process

    /// The process identifier of the launched child.
    var pid: Int32 { process.processIdentifier }

    private init(process: Process) { self.process = process }

    /// Launches an executable with stdin, stdout and stderr on the null device.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable.
    ///   - arguments: Command-line arguments.
    /// - Returns: The running child.
    /// - Throws: Whatever `Process.run()` throws when the executable cannot start.
    static func launch(
        _ executablePath: String,
        _ arguments: [String] = [],
    ) throws -> TestChildProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return .init(process: process)
    }

    /// Kills the child and every process it forked, then reaps the child.
    ///
    /// The descendants are collected before the kill. A dead parent no longer appears in
    /// `pgrep -P`, so its children become unreachable the moment it exits.
    func terminateTree() async {
        // A child that already exited has been reaped, and the kernel is free to hand its number to
        // an unrelated process. Signalling it then hits a stranger.
        guard process.isRunning else {
            process.waitUntilExit()
            return
        }

        let tree = await Self.descendants(of: pid)
        kill(pid, SIGKILL)
        for descendant in tree.reversed() where kill(descendant, 0) == 0 {
            kill(descendant, SIGKILL)
        }
        process.waitUntilExit()
    }

    /// Returns every descendant of a process, parents before their own children.
    static func descendants(of parent: Int32) async -> [Int32] {
        var found: [Int32] = []
        var frontier = await LLDBSession.childPIDs(ofParent: parent)

        while !frontier.isEmpty {
            found += frontier
            var next: [Int32] = []
            for pid in frontier { next += await LLDBSession.childPIDs(ofParent: pid) }
            frontier = next
        }
        return found
    }
}
