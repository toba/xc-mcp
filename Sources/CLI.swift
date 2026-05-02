import Foundation
import Darwin

/// Multicall entry point for all xc-mcp server variants.
///
/// When installed via Homebrew, symlinks like `xc-build`, `xc-debug`, etc. point
/// to the single `xc-mcp` binary. The invoked name (argv[0]) determines which
/// focused server to start. This eliminates shipping 8 identical 24MB binaries.
@main
enum MulticallCLI {
    static func main() async {
        // MCP servers communicate over stdio. If the client half-closes the pipe
        // (e.g. it cancelled the in-flight request and is no longer reading) and
        // we then emit a `notifications/progress`, the kernel raises SIGPIPE.
        // The default disposition terminates the process, which is exactly the
        // failure mode reported in 0xp-xz6: a single user-cancel kills the
        // server for the rest of the session. Switching SIGPIPE to SIG_IGN turns
        // the failed write into an EPIPE that the SDK can surface as an error
        // we already swallow, leaving the server alive.
        signal(SIGPIPE, SIG_IGN)

        let name = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        switch name {
            case "xc-build":
                await BuildServerCLI.main()
            case "xc-debug":
                await DebugServerCLI.main()
            case "xc-device":
                await DeviceServerCLI.main()
            case "xc-project":
                await ProjectServerCLI.main()
            case "xc-simulator":
                await SimulatorServerCLI.main()
            case "xc-strings":
                await StringsServerCLI.main()
            case "xc-swift":
                await SwiftServerCLI.main()
            default:
                await XcodeMCPServerCLI.main()
        }
    }
}
