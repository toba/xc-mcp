import Testing
import Foundation
@testable import XCMCPCore

struct SimulatorPlatformTests {
    // MARK: - Runtime identifier -> platform family

    @Test
    func `iOS runtime maps to iOS Simulator`() {
        let platform = SimulatorPlatform(
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
        )
        #expect(platform == .iOS)
        #expect(platform?.destinationName == "iOS Simulator")
    }

    @Test
    func `xrOS runtime maps to visionOS Simulator`() {
        // The CoreSimulator runtime token is `xrOS`, but the xcodebuild destination is `visionOS`.
        let platform = SimulatorPlatform(
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.xrOS-2-0",
        )
        #expect(platform == .visionOS)
        #expect(platform?.destinationName == "visionOS Simulator")
    }

    @Test
    func `watchOS runtime maps to watchOS Simulator`() {
        let platform = SimulatorPlatform(
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-11-2",
        )
        #expect(platform == .watchOS)
        #expect(platform?.destinationName == "watchOS Simulator")
    }

    @Test
    func `tvOS runtime maps to tvOS Simulator`() {
        let platform = SimulatorPlatform(
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.tvOS-18-1",
        )
        #expect(platform == .tvOS)
        #expect(platform?.destinationName == "tvOS Simulator")
    }

    @Test
    func `unrecognized runtime family yields nil`() {
        #expect(
            SimulatorPlatform(
                runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.fooOS-1-0",
            ) == nil,
        )
    }

    @Test
    func `garbage runtime identifier yields nil`() {
        #expect(SimulatorPlatform(runtimeIdentifier: "not-a-runtime") == nil)
        #expect(SimulatorPlatform(runtimeIdentifier: "") == nil)
    }

    // MARK: - Destination composition

    @Test
    func `resolved simulator composes platform and id destination`() {
        let resolved = ResolvedSimulator(
            udid: "ABC-123", name: "Apple Vision Pro", platform: .visionOS,
        )
        #expect(resolved.destination == "platform=visionOS Simulator,id=ABC-123")
    }
}
