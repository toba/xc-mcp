import Foundation

/// Orders a set of packages so each one comes after every package it depends on
///
/// A pin sweep publishes one layer at a time, because a dependent can only pin a version its
/// dependency has already tagged. That makes the order a correctness requirement, not a
/// presentation choice.
public enum PinGraph {
    /// A dependency cycle, which has no order a sweep can publish in
    public struct Cycle: Error, Sendable, Equatable {
        /// The identities left unordered, sorted by name
        public let identities: [String]

        public init(identities: [String]) { self.identities = identities }
    }

    /// Sorts identities so every dependency precedes the identities that pin it.
    ///
    /// An edge naming an identity outside `edges` is ignored, which is what lets a caller pass the
    /// full pin list of each member and get an order over the members alone.
    ///
    /// - Parameter edges: The identities each identity depends on, keyed by identity.
    /// - Returns: Every identity in `edges`, dependencies first. Identities that could go in either
    ///   order sort by name, so the same input always produces the same order.
    /// - Throws: ``Cycle`` naming the identities that no order satisfies.
    public static func topologicalOrder(
        _ edges: [String: Set<String>]
    ) throws(Cycle) -> [String] {
        var pending = edges.mapValues { $0.intersection(edges.keys) }
        var ordered: [String] = []
        ordered.reserveCapacity(pending.count)

        while !pending.isEmpty {
            let ready = pending.filter { $0.value.isEmpty }.keys.sorted()
            guard !ready.isEmpty else { throw Cycle(identities: pending.keys.sorted()) }
            ordered.append(contentsOf: ready)
            let emitted = Set(ready)
            pending = pending
                .filter { !emitted.contains($0.key) }
                .mapValues { $0.subtracting(emitted) }
        }
        return ordered
    }
}
