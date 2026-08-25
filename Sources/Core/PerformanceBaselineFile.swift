import Foundation

/// One metric's baseline in an `.xcbaseline` run-destination plist.
public struct PerformanceBaselineMetric: Codable, Sendable {
    /// The average Xcode compares a new run against. Absent in a file that records a threshold
    /// alone.
    public var baselineAverage: Double?
    public var maxPercentRegression: Double?
    public var maxPercentRelativeStandardDeviation: Double?

    public init(
        baselineAverage: Double?,
        maxPercentRegression: Double? = nil,
        maxPercentRelativeStandardDeviation: Double? = nil,
    ) {
        self.baselineAverage = baselineAverage
        self.maxPercentRegression = maxPercentRegression
        self.maxPercentRelativeStandardDeviation = maxPercentRelativeStandardDeviation
    }
}

/// An `.xcbaseline` run-destination plist
///
/// Xcode nests a baseline three deep: the test class, then the test method, then the metric
/// identifier. The file carries no other key, so the whole plist decodes into this one field.
public struct PerformanceBaselinePlist: Codable, Sendable {
    /// One test method's baselines, keyed by metric identifier.
    public typealias MetricBaselines = [String: PerformanceBaselineMetric]
    /// One test class's baselines, keyed by test method name.
    public typealias MethodBaselines = [String: MetricBaselines]

    public var classNames: [String: MethodBaselines]

    public init(classNames: [String: MethodBaselines] = [:]) { self.classNames = classNames }

    /// Reads the plist at a path, or an empty one when nothing readable is there.
    public static func read(from path: String) -> PerformanceBaselinePlist {
        guard let data = FileManager.default.contents(atPath: path),
            let plist = try? PropertyListDecoder().decode(Self.self, from: data)
        else { return .init() }
        return plist
    }

    /// Records one metric's baseline, replacing any baseline already under the same three keys.
    public mutating func set(
        _ metric: PerformanceBaselineMetric,
        className: String,
        methodName: String,
        metricIdentifier: String,
    ) { classNames[className, default: [:]][methodName, default: [:]][metricIdentifier] = metric }

    /// Writes the plist as XML, which is the form Xcode reads.
    public func write(to path: String) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: URL(fileURLWithPath: path))
    }
}

/// The machine an `.xcbaseline` was recorded on.
public struct BaselineMachine: Codable, Sendable {
    public var cpuKind: String?
    public var cpuCount: Int?
    public var cpuSpeedInMHz: Int?
    public var modelCode: String?
    public var physicalRAMAmountInMegabytes: Int?

    public init(
        cpuKind: String?,
        cpuCount: Int?,
        cpuSpeedInMHz: Int?,
        modelCode: String?,
        physicalRAMAmountInMegabytes: Int?,
    ) {
        self.cpuKind = cpuKind
        self.cpuCount = cpuCount
        self.cpuSpeedInMHz = cpuSpeedInMHz
        self.modelCode = modelCode
        self.physicalRAMAmountInMegabytes = physicalRAMAmountInMegabytes
    }

    /// The one-line description a baseline listing prints beside a target name.
    public var summary: String { "\(cpuKind ?? "Unknown CPU"), \(modelCode ?? "Unknown")" }
}

/// One run destination in Xcode's `.xcbaseline` `Info.plist` shape.
public struct BaselineRunDestination: Codable, Sendable {
    public var localComputer: BaselineMachine?
    public var targetArchitecture: String?

    public init(localComputer: BaselineMachine?, targetArchitecture: String? = nil) {
        self.localComputer = localComputer
        self.targetArchitecture = targetArchitecture
    }
}

/// An `.xcbaseline` `Info.plist`
///
/// Xcode nests each machine under `runDestinationsByUUID` and a `localComputer` key. This server
/// writes a flat map of run-destination UUID to machine instead, so one file can hold either shape
/// or both. Decoding keeps both, so a write never drops the shape it did not add.
public struct BaselineInfoPlist: Codable, Sendable {
    /// The key Xcode nests its run destinations under.
    private static let destinationsKey = "runDestinationsByUUID"

    public var runDestinationsByUUID: [String: BaselineRunDestination]
    /// The flat shape's machines, keyed by run-destination UUID.
    public var machinesByUUID: [String: BaselineMachine]

    public init(
        runDestinationsByUUID: [String: BaselineRunDestination] = [:],
        machinesByUUID: [String: BaselineMachine] = [:],
    ) {
        self.runDestinationsByUUID = runDestinationsByUUID
        self.machinesByUUID = machinesByUUID
    }

    /// Every machine the file names, keyed by run-destination UUID.
    ///
    /// Xcode's shape wins for a UUID that appears in both shapes.
    public var machineSummaries: [String: String] {
        var summaries = machinesByUUID.mapValues(\.summary)

        for (uuid, destination) in runDestinationsByUUID {
            guard let computer = destination.localComputer else { continue }
            summaries[uuid] = computer.summary
        }
        return summaries
    }

    /// Reads the plist at a path, or an empty one when nothing readable is there.
    public static func read(from path: String) -> BaselineInfoPlist {
        guard let data = FileManager.default.contents(atPath: path),
            let plist = try? PropertyListDecoder().decode(Self.self, from: data)
        else { return .init() }
        return plist
    }

    /// Writes the plist as XML, which is the form Xcode reads.
    public func write(to path: String) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: URL(fileURLWithPath: path))
    }

    /// A coding key for a run-destination UUID, which is a name no enum can spell.
    private struct UUIDKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue _: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: UUIDKey.self)
        runDestinationsByUUID = [:]
        machinesByUUID = [:]

        for key in container.allKeys {
            if key.stringValue == Self.destinationsKey {
                runDestinationsByUUID = try container.decode(
                    [String: BaselineRunDestination].self, forKey: key,
                )
            } else if let machine = try? container.decode(BaselineMachine.self, forKey: key) {
                machinesByUUID[key.stringValue] = machine
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: UUIDKey.self)

        if !runDestinationsByUUID.isEmpty {
            try container.encode(
                runDestinationsByUUID, forKey: UUIDKey(stringValue: Self.destinationsKey),
            )
        }
        for (uuid, machine) in machinesByUUID {
            try container.encode(machine, forKey: UUIDKey(stringValue: uuid))
        }
    }
}
