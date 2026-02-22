import Foundation

/// Paths to open-source fixture repos cloned by `scripts/fetch-fixtures.sh`.
enum IntegrationFixtures {
  /// Root of the xc-mcp package (3 levels up from this file).
  static let projectRoot: String = {
    // #filePath → …/Tests/Integration/IntegrationTestHelper.swift
    let file = URL(fileURLWithPath: #filePath)
    return
      file
      .deletingLastPathComponent()  // Integration/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // project root
      .path
  }()

  static let reposDir = "\(projectRoot)/fixtures/repos"

  // MARK: - Per-repo paths

  static let iceCubesRepoDir = "\(reposDir)/IceCubesApp"
  static let iceCubesProjectPath = "\(iceCubesRepoDir)/IceCubesApp.xcodeproj"

  static let alamofireRepoDir = "\(reposDir)/Alamofire"
  static let alamofireProjectPath = "\(alamofireRepoDir)/Alamofire.xcodeproj"

  static let swiftFormatRepoDir = "\(reposDir)/SwiftFormat"
  static let swiftFormatProjectPath = "\(swiftFormatRepoDir)/SwiftFormat.xcodeproj"

  // MARK: - Preview file paths

  /// A file in the IceCubesApp DesignSystem package that contains a `#Preview` block.
  static let iceCubesPreviewFilePath =
    "\(iceCubesRepoDir)/Packages/DesignSystem/Sources/DesignSystem/Views/PlaceholderView.swift"

  // MARK: - Availability

  /// `true` when all three fixture repos are present on disk.
  static var available: Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: iceCubesProjectPath)
      && fm.fileExists(atPath: alamofireProjectPath)
      && fm.fileExists(atPath: swiftFormatProjectPath)
  }

  // MARK: - Simulator

  /// UDID of an available iPhone simulator, resolved once via `simctl list`.
  /// Prefers stable iOS runtimes (18.x, 19.x) over beta SDKs (26.x) to avoid
  /// swift-frontend crashes in SILGen when building third-party code against
  /// bleeding-edge SDKs.
  static let simulatorUDID: String? = {
    guard
      let output = try? Process.run(
        "/usr/bin/xcrun",
        arguments: ["simctl", "list", "devices", "available", "-j"],
      ),
      let data = output.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let devices = json["devices"] as? [String: [[String: Any]]]
    else { return nil }

    /// Extract iOS version number from runtime key
    /// e.g. "com.apple.CoreSimulator.SimRuntime.iOS-18-5" -> 18
    func iosMajorVersion(_ runtime: String) -> Int? {
      guard runtime.contains("iOS") else { return nil }
      // Split on "-"; the part ending with "iOS" is followed by the major version
      let parts = runtime.split(separator: "-")
      for (i, part) in parts.enumerated() where part.hasSuffix("iOS") {
        if i + 1 < parts.count, let ver = Int(parts[i + 1]) { return ver }
      }
      return nil
    }

    // Sort: prefer stable runtimes (version < 26) over beta, then latest first
    let sortedRuntimes = devices.keys
      .filter { $0.contains("iOS") }
      .sorted { a, b in
        let va = iosMajorVersion(a) ?? 0
        let vb = iosMajorVersion(b) ?? 0
        let aIsStable = va < 26
        let bIsStable = vb < 26
        if aIsStable != bIsStable { return aIsStable }
        return va > vb
      }

    for runtime in sortedRuntimes {
      guard let deviceList = devices[runtime] else { continue }
      for device in deviceList {
        guard
          let name = device["name"] as? String,
          let udid = device["udid"] as? String,
          let isAvailable = device["isAvailable"] as? Bool,
          isAvailable,
          name.contains("iPhone")
        else { continue }
        return udid
      }
    }
    return nil
  }()

  /// `true` when fixtures are available and a simulator UDID was resolved.
  static var simulatorAvailable: Bool {
    available && simulatorUDID != nil
  }
}

// MARK: - Process helper

extension Process {
  /// Run a command synchronously and return stdout as a String.
  fileprivate static func run(_ path: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
  }
}
