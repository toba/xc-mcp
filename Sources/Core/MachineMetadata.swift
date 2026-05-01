import Foundation

/// Retrieves hardware metadata for the current machine via sysctl.
///
/// Used to populate xcbaseline Info.plist run-destination entries
/// so Xcode associates baselines with the correct hardware.
public enum MachineMetadata {
    public struct Info: Sendable {
        public let cpuBrandString: String
        public let coreCount: Int
        public let modelCode: String
        public let ramMegabytes: Int
    }

    public static func current() -> Info {
        Info(
            cpuBrandString: sysctlString("machdep.cpu.brand_string") ?? "Unknown",
            coreCount: sysctlInt("hw.ncpu") ?? 0,
            modelCode: sysctlString("hw.model") ?? "Unknown",
            ramMegabytes: (sysctlInt64("hw.memsize") ?? 0) / 1_048_576,
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        // Truncate at null terminator before decoding
        let length = buffer.firstIndex(of: 0) ?? size
        return String(decoding: buffer[..<length],
                      as: UTF8.self) // sm:ignore useFailableStringInit
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlInt64(_ name: String) -> Int? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
