import XcodeProj
import Foundation

/// Identifies one entry inside a Copy Files build phase
///
/// A caller names an entry by its file name, its path, or the product name of a Swift package
/// product. The remove and platform-filter tools resolve the same argument through here, so both
/// answer the same name with the same entry.
enum CopyFilesPhaseEntry {
    /// Whether `buildFile` answers to `name`.
    static func matches(_ buildFile: PBXBuildFile, name: String) -> Bool {
        if let product = buildFile.product, product.productName == name { return true }
        guard let file = buildFile.file else { return false }
        if file.name == name { return true }
        guard let path = file.path else { return false }
        return path == name || (path as NSString).lastPathComponent == name
    }

    /// Names `buildFile` for result text.
    static func label(for buildFile: PBXBuildFile) -> String {
        if let product = buildFile.product { return product.productName }
        if let file = buildFile.file { return file.path ?? file.name ?? file.uuid }
        return "<dangling \(buildFile.uuid)>"
    }
}
