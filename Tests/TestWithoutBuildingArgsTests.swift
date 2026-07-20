import Testing
@testable import XCMCPCore

/// Covers the `test` / `test-without-building` action selection and selector preservation in
/// ``XcodebuildRunner/testArgs(projectPath:workspacePath:scheme:destination:configuration:onlyTesting:skipTesting:enableCodeCoverage:resultBundlePath:testPlan:withoutBuilding:additionalArguments:)``.
///
/// `projectPath`/`workspacePath` are left nil so the scoped `-derivedDataPath` injection (which
/// depends on the filesystem) stays out of the assembled args and the assertions are deterministic.
struct TestWithoutBuildingArgsTests {
    private func args(withoutBuilding: Bool) -> [String] {
        XcodebuildRunner.testArgs(
            projectPath: nil, workspacePath: nil,
            scheme: "App", destination: "platform=macOS",
            configuration: nil,
            onlyTesting: ["AppTests/FooTests/testBar"],
            skipTesting: ["AppTests/SlowTests"],
            enableCodeCoverage: false, resultBundlePath: nil,
            testPlan: nil, withoutBuilding: withoutBuilding,
            additionalArguments: [],
        )
    }

    @Test func `default action is test`() {
        let a = args(withoutBuilding: false)
        #expect(a.contains("test"))
        #expect(!a.contains("test-without-building"))
    }

    @Test func `without building selects test-without-building action`() {
        let a = args(withoutBuilding: true)
        #expect(a.contains("test-without-building"))
        #expect(!a.contains("test"))
    }

    @Test func `selectors and destination preserved into without-building phase`() {
        let a = args(withoutBuilding: true)
        #expect(a.contains("-scheme"))
        #expect(a.contains("App"))
        #expect(a.contains("-destination"))
        #expect(a.contains("platform=macOS"))
        #expect(a.contains("-only-testing:AppTests/FooTests/testBar"))
        #expect(a.contains("-skip-testing:AppTests/SlowTests"))
    }

    @Test func `action is the final positional before additional arguments`() {
        let a = XcodebuildRunner.testArgs(
            projectPath: nil, workspacePath: nil,
            scheme: "App", destination: "platform=macOS",
            configuration: "Debug",
            onlyTesting: nil, skipTesting: nil,
            enableCodeCoverage: true, resultBundlePath: "/tmp/r.xcresult",
            testPlan: "Perf", withoutBuilding: true,
            additionalArguments: ["-someExtra"],
        )
        // Coverage, result bundle, and test plan still emitted alongside the reuse action.
        #expect(a.contains("-enableCodeCoverage"))
        #expect(a.contains("-resultBundlePath"))
        #expect(a.contains("/tmp/r.xcresult"))
        #expect(a.contains("-testPlan"))
        #expect(a.contains("Perf"))
        // Extra passthrough args follow the action, matching the `test` path.
        let actionIdx = a.firstIndex(of: "test-without-building")
        let extraIdx = a.firstIndex(of: "-someExtra")
        #expect(actionIdx != nil)
        #expect(extraIdx != nil)
        #expect(actionIdx! < extraIdx!)
    }
}
