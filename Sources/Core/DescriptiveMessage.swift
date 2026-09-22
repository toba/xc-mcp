import Foundation

public extension Error {
    /// The text this error carries, preferring what the type states over the bridged fallback.
    ///
    /// `localizedDescription` bridges a plain Swift error through `NSError`. The bridge drops the
    /// text the type provides and leaves an error code, such as
    /// `The operation could not be completed. (XcodeProj.XCodeProjError error 0.)`. The resolved
    /// project path that the error names never reaches the caller, so a missing file and a broken
    /// tool read the same.
    ///
    /// The sources are read in this order:
    ///
    /// 1. `LocalizedError.errorDescription`, the text a type declares for a person to read.
    /// 2. `localizedDescription` for a real `NSError` instance, whose `description` prints the
    ///    domain, the code and the whole user info dictionary instead of the message.
    /// 3. `CustomStringConvertible.description`, which is where the upstream library errors put
    ///    their message.
    /// 4. `String(describing:)`, which prints the case name and its payload for an error that
    ///    declares no text at all.
    var descriptiveMessage: String {
        if let description = (self as? LocalizedError)?.errorDescription { return description }
        // Every Swift error bridges to `NSError` on demand, so `as? NSError` always succeeds. The
        // metatype test is what separates a real `NSError` from a bridged Swift value.
        if type(of: self) is NSError.Type { return localizedDescription }
        if let convertible = self as? CustomStringConvertible { return convertible.description }
        return String(describing: self)
    }
}
