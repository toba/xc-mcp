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

    // (y04-t3c) Archive action runs build then install/codesign — only archive-specific
    // markers signal that the entire archive (including bundle write) is done.
    @Test
    func `Archive action requires archive marker as terminal`() {
        let archiveArgs = ["archive", "-archivePath", "/tmp/x.xcarchive"]
        #expect(!XcodebuildRunner.outputShowsBuildFinished(
            "Build succeeded in 12.3s", arguments: archiveArgs,
        ))
        #expect(!XcodebuildRunner.outputShowsBuildFinished(
            "** BUILD SUCCEEDED **", arguments: archiveArgs,
        ))
        #expect(XcodebuildRunner.outputShowsBuildFinished(
            "** ARCHIVE SUCCEEDED **", arguments: archiveArgs,
        ))
        #expect(XcodebuildRunner.outputShowsBuildFinished(
            "Archive succeeded in 24.0s", arguments: archiveArgs,
        ))
    }

    @Test
    func `Archive failure markers count as terminal`() {
        #expect(XcodebuildRunner.outputShowsBuildFinished("** ARCHIVE FAILED **"))
        #expect(XcodebuildRunner.outputShowsBuildFinished("Archive failed after 3.0s"))
        #expect(XcodebuildRunner.exitCode(forFinishedOutput: "** ARCHIVE FAILED **") == 65)
        #expect(XcodebuildRunner.exitCode(forFinishedOutput: "Archive failed after 3.0s") == 65)
    }
}
