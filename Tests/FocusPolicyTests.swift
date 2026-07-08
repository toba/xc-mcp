import Testing
@testable import XCMCPCore

struct FocusPolicyTests {
    @Test
    func `headless mode is off when env var unset`() {
        #expect(!FocusPolicy.isHeadlessLaunchMode(environment: [:]))
    }

    @Test
    func `headless mode is on for "1"`() {
        #expect(FocusPolicy.isHeadlessLaunchMode(environment: ["XC_MCP_HEADLESS_LAUNCH": "1"]))
    }

    @Test
    func `headless mode is on for "true" case-insensitive`() {
        #expect(FocusPolicy.isHeadlessLaunchMode(environment: ["XC_MCP_HEADLESS_LAUNCH": "TRUE"]))
        #expect(FocusPolicy.isHeadlessLaunchMode(environment: ["XC_MCP_HEADLESS_LAUNCH": "true"]))
    }

    @Test
    func `headless mode is off for "0" or empty`() {
        #expect(!FocusPolicy.isHeadlessLaunchMode(environment: ["XC_MCP_HEADLESS_LAUNCH": "0"]))
        #expect(!FocusPolicy.isHeadlessLaunchMode(environment: ["XC_MCP_HEADLESS_LAUNCH": ""]))
    }

    @Test
    func `openAppArgs returns plain path by default`() {
        let args = FocusPolicy.openAppArgs(appPath: "/Apps/Foo.app", environment: [:])
        #expect(args == ["/Apps/Foo.app"])
    }

    @Test
    func `openAppArgs appends --args when launch args provided`() {
        let args = FocusPolicy.openAppArgs(
            appPath: "/Apps/Foo.app",
            launchArgs: ["--flag", "value"],
            environment: [:],
        )
        #expect(args == ["/Apps/Foo.app", "--args", "--flag", "value"])
    }

    @Test
    func `openAppArgs inserts -g in headless mode`() {
        let args = FocusPolicy.openAppArgs(
            appPath: "/Apps/Foo.app",
            environment: ["XC_MCP_HEADLESS_LAUNCH": "1"],
        )
        #expect(args == ["-g", "/Apps/Foo.app"])
    }

    @Test
    func `openAppArgs preserves --args ordering under headless mode`() {
        let args = FocusPolicy.openAppArgs(
            appPath: "/Apps/Foo.app",
            launchArgs: ["x"],
            environment: ["XC_MCP_HEADLESS_LAUNCH": "1"],
        )
        #expect(args == ["-g", "/Apps/Foo.app", "--args", "x"])
    }

    @Test
    func `openSimulatorAppArgs returns -a Simulator by default`() {
        let args = FocusPolicy.openSimulatorAppArgs(environment: [:])
        #expect(args == ["-a", "Simulator"])
    }

    @Test
    func `openSimulatorAppArgs targets a UDID when provided`() {
        let args = FocusPolicy.openSimulatorAppArgs(simulatorID: "SIM-123", environment: [:])
        #expect(args == ["-a", "Simulator", "--args", "-CurrentDeviceUDID", "SIM-123"])
    }

    @Test
    func `openSimulatorAppArgs returns nil in headless mode`() {
        let args = FocusPolicy.openSimulatorAppArgs(
            environment: ["XC_MCP_HEADLESS_LAUNCH": "1"],
        )
        #expect(args == nil)
    }
}
