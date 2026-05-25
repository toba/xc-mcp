import Testing
@testable import XCMCPCore

/// Covers the post-build "pipes held open" recovery that keeps `build_debug_macos`
/// from aborting a build that actually succeeded when grandchild daemons keep
/// xcodebuild's stdout/stderr open past its terminal status. (qbz-ek1)
struct XcodebuildCompletionDetectionTests {
    @Test
    func `Detects modern Build succeeded marker`() {
        #expect(XcodebuildRunner.outputShowsBuildFinished("Build succeeded in 12.3s"))
    }

    @Test
    func `Detects legacy BUILD SUCCEEDED marker`() {
        #expect(XcodebuildRunner.outputShowsBuildFinished("** BUILD SUCCEEDED **"))
    }

    @Test
    func `Detects build failure markers`() {
        #expect(XcodebuildRunner.outputShowsBuildFinished("** BUILD FAILED **"))
        #expect(XcodebuildRunner.outputShowsBuildFinished("Build failed after 4.1s"))
    }

    @Test
    func `Does not flag in-progress output as finished`() {
        #expect(!XcodebuildRunner.outputShowsBuildFinished(
            "CompileSwiftSources normal arm64 (in target 'App')",
        ))
        #expect(!XcodebuildRunner.outputShowsBuildFinished(""))
    }

    @Test
    func `Exit code is success for completed build`() {
        #expect(XcodebuildRunner.exitCode(forFinishedOutput: "** BUILD SUCCEEDED **") == 0)
        #expect(XcodebuildRunner.exitCode(forFinishedOutput: "Build succeeded in 1.0s") == 0)
    }

    @Test
    func `Exit code reflects build failure`() {
        #expect(XcodebuildRunner.exitCode(forFinishedOutput: "** BUILD FAILED **") == 65)
        #expect(XcodebuildRunner.exitCode(forFinishedOutput: "Build failed after 2.0s") == 65)
    }
}
