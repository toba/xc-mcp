/// An Apple platform a target can be built for
///
/// The raw value is the spelling the MCP tools accept in a `platform` argument, and it matches the
/// name Xcode shows in its destination list.
public enum ApplePlatform: String, Sendable, CaseIterable {
    case iOS
    case macOS
    case tvOS
    case watchOS
    case visionOS

    /// The build setting that carries the minimum OS version for this platform.
    public var deploymentTargetKey: String {
        switch self {
            case .iOS: "IPHONEOS_DEPLOYMENT_TARGET"
            case .macOS: "MACOSX_DEPLOYMENT_TARGET"
            case .tvOS: "TVOS_DEPLOYMENT_TARGET"
            case .watchOS: "WATCHOS_DEPLOYMENT_TARGET"
            case .visionOS: "XROS_DEPLOYMENT_TARGET"
        }
    }

    /// The value of `SDKROOT` for a device build on this platform.
    public var sdkRoot: String {
        switch self {
            case .iOS: "iphoneos"
            case .macOS: "macosx"
            case .tvOS: "appletvos"
            case .watchOS: "watchos"
            case .visionOS: "xros"
        }
    }

    /// The value of `TARGETED_DEVICE_FAMILY`, or `nil` on macOS where the setting means nothing.
    ///
    /// The numbers are the ones Xcode writes: 1 iPhone, 2 iPad, 3 Apple TV, 4 Apple Watch, 7 Apple
    /// Vision.
    public var targetedDeviceFamily: String? {
        switch self {
            case .iOS: "1,2"
            case .macOS: nil
            case .tvOS: "3"
            case .watchOS: "4"
            case .visionOS: "7"
        }
    }

    /// The names a tool description lists, in declaration order.
    public static var allNames: String { allCases.map(\.rawValue).joined(separator: ", ") }
}
