import Foundation

/// Snapshots a `Package.resolved` so a failed resolve can put it back exactly as it was.
///
/// Dropping a pin is a write to a checked-in file. When the resolve that follows fails, leaving the
/// pin dropped would unpin that dependency for every later build, with nothing in the tool result
/// saying so. Taking the bytes first turns the whole operation into one that either lands or leaves
/// no trace.
public struct PinsFileBackup: Sendable {
    /// The pins file path, whether or not a file exists there yet.
    private let path: String
    /// The bytes read at snapshot time, or `nil` when no file existed.
    private let contents: Data?

    /// Snapshots the pins file for a project, workspace, or package root.
    ///
    /// - Parameters:
    ///   - container: Path to the `.xcodeproj`, `.xcworkspace`, or package directory.
    ///   - parser: Locator used to find an existing pins file.
    public init(container: String, parser: PackageResolvedParser = .init()) {
        let existing = parser.locate(for: container)
        path = existing
            ?? PackageResolvedParser.candidateLocations(for: container).first
            ?? (container + "/Package.resolved")
        contents = existing.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
    }

    /// Puts the snapshotted bytes back, or removes the file when none existed at snapshot time.
    ///
    /// - Returns: `true` when the file matches its snapshotted state afterwards.
    @discardableResult
    public func restore() -> Bool {
        let url = URL(fileURLWithPath: path)

        guard let contents else {
            // Nothing existed before, so a file present now is one this operation created.
            guard FileManager.default.fileExists(atPath: path) else { return true }
            return (try? FileManager.default.removeItem(at: url)) != nil
        }

        do {
            try contents.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// Removes pins from a `Package.resolved` file so the next resolve picks a newer version.
///
/// SwiftPM never raises a pin on its own. Resolution reuses whatever `Package.resolved` records,
/// even when the project's requirement allows a newer tag. Dropping one pin makes resolution treat
/// that package as unresolved and choose the newest version the requirement allows, while every
/// other pin stays exactly where it is. That is the surgical form of Xcode's **Update to Latest
/// Package Versions**.
public struct PackageResolvedEditor: Sendable {
    /// Errors surfaced while rewriting a pins file.
    public enum EditError: Error, Equatable, Sendable, LocalizedError {
        case unreadable(String)
        case malformed(String)
        case unwritable(String)

        public var errorDescription: String? {
            switch self {
                case let .unreadable(path): "Cannot read Package.resolved at \(path)"
                case let .malformed(path): "Package.resolved at \(path) is not valid JSON"
                case let .unwritable(path): "Cannot write Package.resolved at \(path)"
            }
        }
    }

    public init() {}

    /// Drops pins from a pins file.
    ///
    /// - Parameters:
    ///   - path: Path to the `Package.resolved` file.
    ///   - identities: Package identities to drop, or `nil` to drop every pin.
    /// - Returns: The identities actually removed, sorted.
    /// - Throws: ``EditError`` when the file cannot be read, parsed, or written.
    public func removePins(
        fileAt path: String,
        identities: Set<String>?,
    ) throws(EditError) -> [String] {
        let data: Data

        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw .unreadable(path)
        }

        // A pins file carries fields this editor never reads, and SwiftPM rewrites the whole file
        // from what it finds there. Decoding into an AnyValue tree keeps every one of them, which a
        // model naming only `pins` and `identity` would drop on the write below.
        var root: [String: AnyValue]

        do {
            root = try JSONDecoder().decode([String: AnyValue].self, from: data)
        } catch {
            throw .malformed(path)
        }

        var removed: [String] = []

        // v2/v3: pins live at the top level. v1: they live under `object.pins`.
        if let pins = root["pins"]?.arrayValue {
            root["pins"] = filter(pins, identities: identities, removed: &removed)
        } else if var container = root["object"]?.dictionaryValue,
           let pins = container["pins"]?.arrayValue
        {
            container["pins"] = filter(pins, identities: identities, removed: &removed)
            root["object"] = .dictionary(container)
        } else {
            throw .malformed(path)
        }

        guard !removed.isEmpty else { return [] }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(root).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw .unwritable(path)
        }
        return removed.sorted()
    }

    /// Keeps the pins that survive, and records the identity of each one dropped.
    private func filter(
        _ pins: [AnyValue],
        identities: Set<String>?,
        removed: inout [String],
    ) -> AnyValue {
        .array(pins.filter { pin in
            guard let pin = pin.dictionaryValue else { return true }
            let identity = Self.identity(of: pin)

            guard let identities else {
                removed.append(identity)
                return false
            }

            if identities.contains(identity) {
                removed.append(identity)
                return false
            }
            return true
        })
    }

    /// Reads a pin's identity, deriving it from the location when the field is absent (v1 files).
    static func identity(of pin: [String: AnyValue]) -> String {
        if let identity = pin["identity"]?.stringValue { return identity.lowercased() }
        let location = pin["location"]?.stringValue ?? pin["repositoryURL"]?.stringValue ?? ""
        return PackageResolvedParser.identity(forURL: location)
    }
}
