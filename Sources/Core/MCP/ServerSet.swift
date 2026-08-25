/// The servers that expose a tool
///
/// A tool belongs to the monolithic `xc-mcp` server, to one or more focused servers, or to both.
/// ``ToolRegistration`` carries this set, so a server selects its tools by membership instead of
/// restating them in an enum and a descriptor array.
public struct ServerSet: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let monolith = ServerSet(rawValue: 1 << 0)
    public static let build = ServerSet(rawValue: 1 << 1)
    public static let debug = ServerSet(rawValue: 1 << 2)
    public static let device = ServerSet(rawValue: 1 << 3)
    public static let project = ServerSet(rawValue: 1 << 4)
    public static let simulator = ServerSet(rawValue: 1 << 5)
    public static let strings = ServerSet(rawValue: 1 << 6)
    public static let swift = ServerSet(rawValue: 1 << 7)

    /// Every focused server, without the monolith.
    public static let allFocused: ServerSet = [
        .build, .debug, .device, .project, .simulator, .strings, .swift,
    ]

    /// The single members of this set, in declaration order.
    public var members: [ServerSet] { Self.ordered.filter { contains($0) } }

    /// The executable name clients invoke this server as.
    ///
    /// Returns `nil` for a set that holds anything other than one member.
    public var executableName: String? {
        switch self {
            case .monolith: "xc-mcp"
            case .build: "xc-build"
            case .debug: "xc-debug"
            case .device: "xc-device"
            case .project: "xc-project"
            case .simulator: "xc-simulator"
            case .strings: "xc-strings"
            case .swift: "xc-swift"
            default: nil
        }
    }

    private static let ordered: [ServerSet] = [
        .monolith, .build, .debug, .device, .project, .simulator, .strings, .swift,
    ]
}
