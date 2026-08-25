import XcodeProj
import Foundation

/// A Swift package reference an Xcode project holds, remote or local
///
/// The two kinds sit in separate arrays on `PBXProject` and carry a different identifying field.
/// Everything the add and remove tools do around them is otherwise the same, so those tools work
/// against this protocol and each conformance supplies the differences. A caller names the array
/// itself with a key path, because a protocol requirement returning `Self` cannot be witnessed by a
/// non-final class.
public protocol PackageReferencing: PBXContainerItem {
    /// The value that identifies one reference, a repository URL or a relative path
    var packageIdentifier: String { get }
    /// The package traits the project enables
    var traits: [String]? { get set }
    /// Name of the kind mid-sentence, such as `local Swift Package`
    static var noun: String { get }

    /// Whether a target's product dependency comes from this reference
    ///
    /// - Parameter dependency: One entry of a target's `packageProductDependencies`.
    func owns(_ dependency: XCSwiftPackageProductDependency) -> Bool
}

public extension PackageReferencing {
    /// `noun` with its first character uppercased, for the start of a sentence
    static var capitalizedNoun: String { noun.prefix(1).uppercased() + noun.dropFirst() }
}

extension XCRemoteSwiftPackageReference: PackageReferencing {
    public var packageIdentifier: String { repositoryURL ?? "" }

    public static var noun: String { "Swift Package" }

    public func owns(_ dependency: XCSwiftPackageProductDependency) -> Bool {
        dependency.package === self
    }
}

extension XCLocalSwiftPackageReference: PackageReferencing {
    public var packageIdentifier: String { relativePath }

    public static var noun: String { "local Swift Package" }

    /// A local package product carries no package reference, so it is matched by product name,
    /// which conventionally equals the package directory name.
    public func owns(_ dependency: XCSwiftPackageProductDependency) -> Bool {
        dependency.package == nil
            && dependency.productName == URL(fileURLWithPath: relativePath).lastPathComponent
    }
}
