import Foundation

/// Whether the `sm` (swiftiomatic) binary is installed.
///
/// A test that shells out to `sm` carries `.enabled(if: InstalledSm.isAvailable)`, so the suite
/// still passes on a machine without the tool.
enum InstalledSm {
    static let isAvailable = FileManager.default.isExecutableFile(
        atPath: "/opt/homebrew/bin/sm",
    ) || which("sm")

    /// Returns true when `which` reports a path for the named binary.
    private static func which(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
