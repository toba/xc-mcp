import Foundation

public extension CaseIterable where Self: RawRepresentable, RawValue == String {
    /// The case names a tool description or an error message lists, in declaration order.
    ///
    /// Every enum a tool exposes as a schema `enum` needs this same sentence fragment, so the join
    /// lives here rather than once per enum.
    static var allNames: String { allCases.map(\.rawValue).joined(separator: ", ") }
}
