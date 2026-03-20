import Foundation

/// Multicall entry point for all xc-mcp server variants.
///
/// When installed via Homebrew, symlinks like `xc-build`, `xc-debug`, etc. point
/// to the single `xc-mcp` binary. The invoked name (argv[0]) determines which
/// focused server to start. This eliminates shipping 8 identical 24MB binaries.
@main
enum MulticallCLI {
    static func main() async {
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
