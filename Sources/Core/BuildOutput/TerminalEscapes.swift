/// Removes the escape sequences a compiler writes to color its diagnostics.
///
/// `swiftc` colors a diagnostic whenever it believes a terminal reads its output, and a build the
/// server runs through a pipe still inherits that decision from the parent process. The escape
/// bytes then sit inside the file name and the message, so a reported line reads back as
/// `\u{1B}[0;1m/path/File.swift:12:5: \u{1B}[0;1;31merror: …`. A caller that greps such a line has
/// to strip the codes first, and a reader of the response sees them raw.
public enum TerminalEscapes {
    private static let escape = UInt8(0x1B)
    private static let leftBracket = UInt8(ascii: "[")
    private static let rightBracket = UInt8(ascii: "]")
    private static let backslash = UInt8(ascii: "\\")
    private static let bell = UInt8(0x07)

    /// Returns `text` without its escape sequences.
    ///
    /// Text that holds no escape byte comes back unchanged, so the common line costs one scan and
    /// no allocation.
    public static func stripped(_ text: String) -> String {
        guard text.utf8.contains(escape) else { return text }
        // A native string lends its bytes, so a colored line costs no copy of the input. A string
        // bridged from NSString lends nothing, and the fallback copies once.
        if let result = text.utf8.withContiguousStorageIfAvailable({ dropEscapes(in: $0) }) {
            return result
        }
        return Array(text.utf8).withUnsafeBufferPointer { dropEscapes(in: $0) }
    }

    /// Returns the bytes of `source` without their escape sequences, decoded as UTF-8.
    private static func dropEscapes(in source: UnsafeBufferPointer<UInt8>) -> String {
        var kept: [UInt8] = []
        kept.reserveCapacity(source.count)
        var index = 0

        while index < source.count {
            guard source[index] == escape else {
                kept.append(source[index])
                index += 1
                continue
            }
            index += 1
            guard index < source.count else { break }

            switch source[index] {
                case leftBracket: index = endOfControlSequence(in: source, from: index + 1)
                case rightBracket: index = endOfOperatingSystemCommand(in: source, from: index + 1)
                // every other escape is two bytes wide, so dropping the second ends it
                default: index += 1
            }
        }
        return .init(decoding: kept, as: UTF8.self)  // sm:ignore useFailableStringInit
    }

    /// Returns the index one past a CSI sequence, whose parameter bytes run until a final byte in
    /// the `@` to `~` range.
    private static func endOfControlSequence(
        in source: UnsafeBufferPointer<UInt8>,
        from start: Int,
    ) -> Int {
        var index = start
        while index < source.count, !(0x40...0x7E).contains(source[index]) { index += 1 }
        return index < source.count ? index + 1 : index
    }

    /// Returns the index one past an OSC sequence, which ends on a bell or on `ESC \`.
    private static func endOfOperatingSystemCommand(
        in source: UnsafeBufferPointer<UInt8>,
        from start: Int,
    ) -> Int {
        var index = start

        while index < source.count {
            if source[index] == bell { return index + 1 }

            if source[index] == escape, index + 1 < source.count, source[index + 1] == backslash {
                return index + 2
            }
            index += 1
        }
        return index
    }
}
