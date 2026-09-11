import Foundation

/// One dependency's resolved pin moving
///
/// A move comes from one of two places. A diff of `Package.resolved` before and after a resolve
/// reports what did move, and the report `swift package update --dry-run` prints says what would
/// move. Both arrive here so a caller never diffs the pins file itself.
public struct PinMove: Sendable, Equatable {
    /// Which way the pin moved
    public enum Kind: Sendable, Equatable {
        /// The pins file gained an entry
        case added
        /// The entry's version, branch or revision changed
        case updated
        /// The pins file lost an entry
        case removed
    }

    /// SwiftPM package identity, such as `toba-data`
    public let name: String
    public let kind: Kind

    /// The state the pin held before, absent for an addition
    public let from: String?

    /// The state the pin holds after, absent for a removal
    public let to: String?

    public init(name: String, kind: Kind, from: String? = nil, to: String? = nil) {
        self.name = name
        self.kind = kind
        self.from = from
        self.to = to
    }

    public static func added(_ name: String, to state: String?) -> PinMove {
        .init(name: name, kind: .added, to: state)
    }

    public static func updated(_ name: String, from old: String?, to new: String?) -> PinMove {
        .init(name: name, kind: .updated, from: old, to: new)
    }

    public static func removed(_ name: String, from state: String?) -> PinMove {
        .init(name: name, kind: .removed, from: state)
    }

    /// Renders the move as one indented report line
    public var reportLine: String {
        switch kind {
            case .added: to.map { "  + \(name) \($0)" } ?? "  + \(name)"
            case .updated: "  ~ \(name) \(from ?? "?") → \(to ?? "?")"
            case .removed:
                from.map { "  - \(name) \($0) (no longer pinned)" }
                    ?? "  - \(name) (no longer pinned)"
        }
    }
}

public extension PinMove {
    /// Reports every pin whose resolved state differs between two readings of a pins file.
    ///
    /// - Parameters:
    ///   - before: The pins read before the resolve, keyed by identity.
    ///   - after: The pins read after the resolve, keyed by identity.
    /// - Returns: The moves, with the additions and the updates first, each group sorted by name.
    static func moves(
        from before: [String: ResolvedPin],
        to after: [String: ResolvedPin],
    ) -> [PinMove] {
        var moves: [PinMove] = []

        for identity in after.keys.sorted() {
            guard let new = after[identity] else { continue }

            guard let old = before[identity] else {
                moves.append(.added(identity, to: new.stateDescription))
                continue
            }

            if old.stateDescription != new.stateDescription {
                moves.append(.updated(
                    identity, from: old.stateDescription, to: new.stateDescription))
            }
        }

        for identity in before.keys.sorted() where after[identity] == nil {
            moves.append(.removed(identity, from: before[identity]?.stateDescription))
        }
        return moves
    }

    /// Reads the moves out of the report `swift package update` prints.
    ///
    /// The report opens with a count line and then holds one line per change, marked `+`, `~` or
    /// `-`. An updated line carries the arrow, and SwiftPM has printed the name on both sides of it
    /// in some releases, so the parse drops a repeat of the name rather than reading it as part of
    /// the new state.
    ///
    /// - Parameter output: The command's combined output.
    /// - Returns: The moves the report names, in the order it prints them.
    static func planned(fromReport output: String) -> [PinMove] {
        output.split(separator: "\n").compactMap { planned(fromLine: String($0)) }
    }

    /// Reads one report line, or returns nil when the line marks no change.
    ///
    /// The marker needs its trailing space. A flag such as `--dry-run` echoed into the output opens
    /// with the same character as a removal.
    static func planned(fromLine line: String) -> PinMove? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, trimmed.dropFirst().first == " " else { return nil }
        let body = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        switch marker {
            case "+": return name(of: body).map { .added($0.name, to: $0.rest) }
            case "-": return name(of: body).map { .removed($0.name, from: $0.rest) }
            case "~": return update(from: body)
            default: return nil
        }
    }

    /// Splits a report line's body into the identity and whatever states follow it.
    ///
    /// One split keeps the tail whole, so a state of several words survives without a rejoin.
    private static func name(of body: String) -> (name: String, rest: String?)? {
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let name = parts.first else { return nil }
        return (String(name), parts.count > 1 ? String(parts[1]) : nil)
    }

    /// Reads an updated line, whose two sides sit either side of the arrow.
    private static func update(from body: String) -> PinMove? {
        let sides = body.components(separatedBy: " -> ")
        guard sides.count == 2,
              let left = name(of: sides[0]),
              let right = name(of: sides[1]) else { return nil }

        // SwiftPM has printed the identity on both sides of the arrow in some releases, so a repeat
        // of it belongs to neither state.
        let to = right.name == left.name ? right.rest : sides[1]
        return .updated(left.name, from: left.rest, to: to)
    }

    /// Renders a report block for a set of moves.
    ///
    /// - Parameters:
    ///   - moves: The moves to list.
    ///   - header: The line that opens the list.
    ///   - whenEmpty: The one line to return when nothing moved.
    static func lines(
        _ moves: [PinMove],
        header: String,
        whenEmpty: String,
    ) -> [String] { moves.isEmpty ? [whenEmpty] : [header] + moves.map(\.reportLine) }
}
