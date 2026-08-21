import Testing
import Foundation
@testable import XCMCPCore

struct GitRunnerTests {
    @Test func `parses tags newest first`() {
        let output = """
            aaa\trefs/tags/1.0.0
            bbb\trefs/tags/2.1.0
            ccc\trefs/tags/2.2.0
            """
        let tags = GitRunner.parseTags(output)
        #expect(tags.map(\.description) == ["2.2.0", "2.1.0", "1.0.0"])
    }

    @Test func `folds a peeled tag into the tag it annotates`() {
        let output = """
            aaa\trefs/tags/2.2.0
            bbb\trefs/tags/2.2.0^{}
            """
        #expect(GitRunner.parseTags(output).count == 1)
    }

    @Test func `drops a tag that is not a version`() {
        let output = """
            aaa\trefs/tags/nightly
            bbb\trefs/tags/1.0.0
            ccc\trefs/heads/main
            """
        #expect(GitRunner.parseTags(output).map(\.description) == ["1.0.0"])
    }

    @Test func `returns nothing for empty output`() {
        #expect(GitRunner.parseTags("").isEmpty)
    }
}
