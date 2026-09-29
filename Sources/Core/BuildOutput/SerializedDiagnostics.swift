import Foundation

/// Decodes the serialized diagnostics (`.dia`) files that `swift-frontend` and `clang` write
/// beside each object file.
///
/// A `.dia` file is an LLVM bitstream. Xcode used to ship `c-index-test` to decode it, and current
/// toolchains do not, so the build tools read the format here instead of shelling out.
///
/// The layout, from `clang/Frontend/SerializedDiagnostics.h`:
///
/// - The magic `DIAG`, then top-level blocks with a 2-bit abbreviation width.
/// - A `BLOCKINFO` block (id 0) that defines abbreviations for the other blocks.
/// - A meta block (id 8) with the format version.
/// - One diagnostic block (id 9) per top-level diagnostic. Its notes nest inside it as further
///   diagnostic blocks.
public enum SerializedDiagnostics {
    /// How serious a diagnostic is.
    public enum Severity: Int, Sendable {
        case ignored = 0, note, warning, error, fatal, remark

        /// The label a compiler prints for this severity.
        public var label: String {
            switch self {
                case .ignored: "ignored"
                case .note: "note"
                case .warning: "warning"
                case .error: "error"
                case .fatal: "fatal error"
                case .remark: "remark"
            }
        }
    }

    /// One diagnostic and the notes attached to it.
    public struct Diagnostic: Sendable, Equatable {
        public var severity: Severity
        public var file: String?
        public var line: Int
        public var column: Int
        public var message: String
        public var flag: String?
        public var category: String?
        public var notes: [Diagnostic]

        /// The diagnostic in compiler form, with each note on an indented line below it.
        public func formatted(indent: String = "") -> String {
            var location = ""
            if let file {
                location = "\(file):"
                if line > 0 { location += "\(line):\(column):" }
                location += " "
            }
            var text = "\(indent)\(location)\(severity.label): \(message)"
            if let flag, !flag.isEmpty { text += " [\(flag)]" }
            for note in notes { text += "\n" + note.formatted(indent: indent + "  ") }
            return text
        }

        /// This diagnostic and all its notes, depth first.
        public var flattened: [Diagnostic] { [self] + notes.flatMap(\.flattened) }
    }

    /// Why a file could not be decoded.
    public enum DecodeError: Error, Equatable, CustomStringConvertible {
        case notSerializedDiagnostics
        case truncated
        case malformed(String)

        public var description: String {
            switch self {
                case .notSerializedDiagnostics: "the file does not start with the DIAG magic"
                case .truncated: "the file ends inside a record"
                case let .malformed(detail): "the bitstream is malformed: \(detail)"
            }
        }
    }

    /// Decodes the file at `path`.
    public static func decode(contentsOf path: String) throws -> [Diagnostic] {
        try decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
    }

    /// Decodes the bytes of one `.dia` file.
    ///
    /// - Parameter bytes: The file contents.
    /// - Returns: The top-level diagnostics in file order.
    /// - Throws: ``DecodeError`` when the bytes are not a well-formed diagnostics bitstream.
    public static func decode(_ bytes: [UInt8]) throws(DecodeError) -> [Diagnostic] {
        guard bytes.count >= 4, bytes[0] == 0x44, bytes[1] == 0x49, bytes[2] == 0x41,
              bytes[3] == 0x47
        else { throw .notSerializedDiagnostics }

        var decoder = Decoder(reader: BitReader(bytes: bytes, bitPosition: 32))
        try decoder.readTopLevel()
        return decoder.diagnostics
    }

    /// Reports whether the raw bytes of a `.dia` file hold `text`.
    ///
    /// A diagnostic message sits in the file as a plain blob, so a byte search finds one without a
    /// decode. The build tools use this to pick the few files worth decoding out of thousands.
    public static func fileContains(_ text: String, atPath path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path) else { return false }
        return data.contains(text.utf8)
    }

    // MARK: - Record ids

    private enum BlockID {
        static let blockInfo: UInt64 = 0
        static let meta: UInt64 = 8
        static let diagnostic: UInt64 = 9
    }

    private enum RecordCode {
        static let diagnostic: UInt64 = 2
        static let diagnosticFlag: UInt64 = 4
        static let category: UInt64 = 5
        static let filename: UInt64 = 6
        static let blockInfoSetBID: UInt64 = 1
    }
}

// MARK: - Bitstream

extension SerializedDiagnostics {
    /// Reads bits least significant first, the order LLVM writes them.
    struct BitReader {
        let bytes: [UInt8]
        var bitPosition: Int

        var isAtEnd: Bool { bitPosition >= bytes.count * 8 }

        mutating func read(_ width: Int) throws(DecodeError) -> UInt64 {
            guard width > 0 else { return 0 }
            guard width <= 64 else { throw .malformed("a fixed field is \(width) bits wide") }
            guard bitPosition + width <= bytes.count * 8 else { throw .truncated }

            var value: UInt64 = 0
            var written = 0

            while written < width {
                let byte = bytes[bitPosition >> 3]
                let offset = bitPosition & 7
                let take = min(8 - offset, width - written)
                let chunk = (UInt64(byte) >> UInt64(offset)) & ((1 << UInt64(take)) - 1)
                value |= chunk << UInt64(written)
                written += take
                bitPosition += take
            }
            return value
        }

        mutating func readVBR(_ width: Int) throws(DecodeError) -> UInt64 {
            guard width >= 2 else { throw .malformed("a VBR field is \(width) bits wide") }
            let continuation: UInt64 = 1 << UInt64(width - 1)
            var value: UInt64 = 0
            var shift: UInt64 = 0

            while true {
                let chunk = try read(width)
                value |= (chunk & (continuation - 1)) << shift
                if chunk & continuation == 0 { return value }
                shift += UInt64(width - 1)
                guard shift < 64 else { throw .malformed("a VBR value overflows 64 bits") }
            }
        }

        mutating func alignTo32Bits() { bitPosition = (bitPosition + 31) & ~31 }

        mutating func readBytes(_ count: Int) throws(DecodeError) -> ArraySlice<UInt8> {
            let start = bitPosition >> 3
            guard start + count <= bytes.count else { throw .truncated }
            bitPosition += count * 8
            return bytes[start..<(start + count)]
        }
    }

    /// One operand of an abbreviation.
    enum AbbreviationOperand {
        case literal(UInt64)
        case fixed(Int)
        case vbr(Int)
        case array
        case char6
        case blob
    }

    /// One record, with its code, its scalar operands, and its blob when it has one.
    struct Record {
        var code: UInt64
        var operands: [UInt64]
        var blob: ArraySlice<UInt8>?

        /// The record text: the blob when present, else the operands read as characters.
        func text(droppingOperands leading: Int) -> String {
            if let blob { return Self.decodeUTF8(blob) }
            return Self.decodeUTF8(operands.dropFirst(leading).map { UInt8(truncatingIfNeeded: $0) })
        }

        /// Decodes UTF-8 text, keeping a message that holds an invalid byte.
        ///
        /// A diagnostic is worth more with one replacement character than not at all, so the
        /// lossy decode is the fallback for bytes that fail validation.
        static func decodeUTF8(_ bytes: some Collection<UInt8>) -> String {
            if let text = String(validating: bytes, as: UTF8.self) { return text }
            return String(decoding: bytes, as: UTF8.self)  // sm:ignore useFailableStringInit
        }
    }

    /// Walks the blocks of one file and collects its diagnostics.
    struct Decoder {
        var reader: BitReader
        var diagnostics: [Diagnostic] = []
        var files: [UInt64: String] = [:]
        var flags: [UInt64: String] = [:]
        var categories: [UInt64: String] = [:]
        var blockInfoAbbreviations: [UInt64: [[AbbreviationOperand]]] = [:]

        mutating func readTopLevel() throws(DecodeError) {
            while !reader.isAtEnd {
                // Trailing padding shorter than one abbreviation id ends the stream.
                guard reader.bytes.count * 8 - reader.bitPosition >= 2 else { return }
                let id = try reader.read(2)

                switch id {
                    case 1:
                        let blockID = try reader.readVBR(8)
                        if let diagnostic = try readBlock(blockID) {
                            diagnostics.append(diagnostic)
                        }
                    case 0:
                        // An END_BLOCK at top level is padding. Stop at it.
                        return
                    default:
                        throw .malformed("abbreviation id \(id) at top level")
                }
            }
        }

        /// Reads one block after its ENTER_SUBBLOCK id, returning the diagnostic it holds.
        mutating func readBlock(_ blockID: UInt64) throws(DecodeError) -> Diagnostic? {
            let width = Int(try reader.readVBR(4))
            reader.alignTo32Bits()
            let lengthInWords = Int(try reader.read(32))

            guard blockID == BlockID.blockInfo || blockID == BlockID.meta
                || blockID == BlockID.diagnostic
            else {
                // Skip a block this reader does not know.
                reader.bitPosition += lengthInWords * 32
                return nil
            }

            var abbreviations = blockInfoAbbreviations[blockID] ?? []
            var blockInfoTarget: UInt64?
            var current: Diagnostic?
            var notes: [Diagnostic] = []

            while true {
                let id = try reader.read(width)

                switch id {
                    case 0:
                        reader.alignTo32Bits()
                        guard var diagnostic = current else { return nil }
                        diagnostic.notes += notes
                        return diagnostic
                    case 1:
                        let child = try reader.readVBR(8)
                        if let note = try readBlock(child) { notes.append(note) }
                    case 2:
                        let abbreviation = try readAbbreviationDefinition()
                        if blockID == BlockID.blockInfo {
                            guard let target = blockInfoTarget else {
                                throw .malformed("a BLOCKINFO abbreviation before SETBID")
                            }
                            blockInfoAbbreviations[target, default: []].append(abbreviation)
                        } else {
                            abbreviations.append(abbreviation)
                        }
                    default:
                        let record: Record
                        if id == 3 {
                            record = try readUnabbreviatedRecord()
                        } else {
                            let index = Int(id) - 4
                            guard abbreviations.indices.contains(index) else {
                                throw .malformed("undefined abbreviation id \(id)")
                            }
                            record = try readRecord(abbreviations[index])
                        }

                        if blockID == BlockID.blockInfo {
                            if record.code == RecordCode.blockInfoSetBID {
                                blockInfoTarget = record.operands.first
                            }
                        } else if blockID == BlockID.diagnostic {
                            apply(record, to: &current)
                        }
                }
            }
        }

        mutating func apply(_ record: Record, to current: inout Diagnostic?) {
            let operands = record.operands

            switch record.code {
                case RecordCode.diagnostic:
                    // [severity, file, line, column, offset, category, flag, length, text]
                    guard operands.count >= 7 else { return }
                    let fileID = operands[1]
                    current = Diagnostic(
                        severity: Severity(rawValue: Int(operands[0])) ?? .error,
                        file: fileID == 0 ? nil : files[fileID],
                        line: Int(operands[2]),
                        column: Int(operands[3]),
                        message: record.text(droppingOperands: 8),
                        flag: operands[6] == 0 ? nil : flags[operands[6]],
                        category: operands[5] == 0 ? nil : categories[operands[5]],
                        notes: [],
                    )
                case RecordCode.filename:
                    // [id, size, modification time, length, name]
                    guard let id = operands.first else { return }
                    files[id] = record.text(droppingOperands: 4)
                case RecordCode.diagnosticFlag:
                    // [id, length, name]
                    guard let id = operands.first else { return }
                    flags[id] = record.text(droppingOperands: 2)
                case RecordCode.category:
                    // [id, length, name]
                    guard let id = operands.first else { return }
                    categories[id] = record.text(droppingOperands: 2)
                default:
                    // Source ranges and fix-its do not reach the report.
                    return
            }
        }

        mutating func readAbbreviationDefinition() throws(DecodeError) -> [AbbreviationOperand] {
            let count = Int(try reader.readVBR(5))
            var operands: [AbbreviationOperand] = []
            operands.reserveCapacity(count)

            for _ in 0..<count {
                if try reader.read(1) == 1 {
                    operands.append(.literal(try reader.readVBR(8)))
                    continue
                }
                switch try reader.read(3) {
                    case 1: operands.append(.fixed(Int(try reader.readVBR(5))))
                    case 2: operands.append(.vbr(Int(try reader.readVBR(5))))
                    case 3: operands.append(.array)
                    case 4: operands.append(.char6)
                    case 5: operands.append(.blob)
                    case let encoding: throw .malformed("operand encoding \(encoding)")
                }
            }
            return operands
        }

        mutating func readUnabbreviatedRecord() throws(DecodeError) -> Record {
            let code = try reader.readVBR(6)
            let count = Int(try reader.readVBR(6))
            var operands: [UInt64] = []
            operands.reserveCapacity(count)
            for _ in 0..<count { operands.append(try reader.readVBR(6)) }
            return Record(code: code, operands: operands, blob: nil)
        }

        mutating func readRecord(_ abbreviation: [AbbreviationOperand]) throws(DecodeError)
            -> Record
        {
            var values: [UInt64] = []
            var blob: ArraySlice<UInt8>?
            var index = 0

            while index < abbreviation.count {
                switch abbreviation[index] {
                    case .array:
                        guard index + 1 < abbreviation.count else {
                            throw .malformed("an array operand without an element type")
                        }
                        let element = abbreviation[index + 1]
                        let length = Int(try reader.readVBR(6))
                        for _ in 0..<length { values.append(try readScalar(element)) }
                        index += 2
                        continue
                    case .blob:
                        let length = Int(try reader.readVBR(6))
                        reader.alignTo32Bits()
                        blob = try reader.readBytes(length)
                        reader.alignTo32Bits()
                    case let operand:
                        values.append(try readScalar(operand))
                }
                index += 1
            }

            guard let code = values.first else { throw .malformed("a record without a code") }
            return Record(code: code, operands: Array(values.dropFirst()), blob: blob)
        }

        mutating func readScalar(_ operand: AbbreviationOperand) throws(DecodeError) -> UInt64 {
            switch operand {
                case let .literal(value): return value
                case let .fixed(width): return try reader.read(width)
                case let .vbr(width): return try reader.readVBR(width)
                case .char6: return Self.char6(try reader.read(6))
                case .array, .blob: throw .malformed("a nested array or blob operand")
            }
        }

        /// Maps a 6-bit value to its character in `[a-zA-Z0-9._]`.
        static func char6(_ value: UInt64) -> UInt64 {
            switch value {
                case 0..<26: UInt64(UInt8(ascii: "a")) + value
                case 26..<52: UInt64(UInt8(ascii: "A")) + value - 26
                case 52..<62: UInt64(UInt8(ascii: "0")) + value - 52
                case 62: UInt64(UInt8(ascii: "."))
                default: UInt64(UInt8(ascii: "_"))
            }
        }
    }
}
