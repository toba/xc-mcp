import TobaCore
import TobaHash
public import Foundation

/// A short hexadecimal key derived from a string.
///
/// The key names a cache directory, so it must stay the same across runs of the server and across
/// machines. It guards nothing, so it needs no resistance to a forged preimage. `StableHasher` is a
/// non-cryptographic xxHash64, which meets both requirements and costs less than a digest.
///
/// `DerivedDataScoper`, `TestResultBundleScoper` and `DetectUnusedCodeTool` each derived this key
/// with their own copy of the same function. One definition keeps their output identical.
public enum ShortHash {
    /// Number of hash bytes the key spells out.
    private static let byteCount = 6

    /// A 12-character lower-case hexadecimal key for `value`.
    ///
    /// The width matches Xcode's own DerivedData naming style closely enough to look familiar.
    public static func hex(of value: String) -> String {
        let hash = StableHasher.hash(Bytes(value.utf8))
        // Big-endian first, so the leading characters vary with the high-order bits. A
        // little-endian read would put the least significant byte first and cluster the prefix.
        let bytes: Bytes = withUnsafeBytes(of: hash.bigEndian, Array.init)
        return Data(bytes.prefix(byteCount)).hexString(uppercase: false)
    }
}
