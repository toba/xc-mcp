import Testing
@testable import XCMCPCore

/// Tests for the compact elapsed-duration rendering used on build/test/clean result lines
/// (issue 5t9-9ll).
struct ElapsedFormattingTests {
    @Test
    func `sub-minute durations render as seconds with one decimal`() {
        #expect(Duration.seconds(12.4).elapsedDescription == "12.4s")
        #expect(Duration.milliseconds(31).elapsedDescription == "0.0s")
        #expect(Duration.seconds(0.5).elapsedDescription == "0.5s")
        #expect(Duration.seconds(59.9).elapsedDescription == "59.9s")
    }

    @Test
    func `minute-and-over durations render as minutes and seconds`() {
        #expect(Duration.seconds(60).elapsedDescription == "1m0s")
        #expect(Duration.seconds(75).elapsedDescription == "1m15s")
        #expect(Duration.seconds(605).elapsedDescription == "10m5s")
    }
}
