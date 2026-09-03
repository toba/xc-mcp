import Foundation

/// Splits raw build log text into lines.
public enum BuildLogLines {
    /// Returns the lines of `input`, without their line terminators and without their terminal
    /// escape sequences.
    ///
    /// Swift reads `\r\n` as one `Character`, and that grapheme is not equal to `"\n"`. A CRLF log
    /// split on the `"\n"` character therefore comes back as one line, and every diagnostic in it
    /// goes unreported. This splits on the newline byte instead, then drops the carriage return the
    /// split leaves at the end of each line.
    ///
    /// Each line then loses its escape sequences. A colored diagnostic carries them inside the file
    /// name, so a parser that keeps them reports a path no editor opens. See `TerminalEscapes`.
    ///
    /// The result keeps empty lines, so a line index matches the source line number.
    public static func split(_ input: String) -> [String] {
        input.utf8
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { line in
                let body = line.last == UInt8(ascii: "\r") ? line.dropLast() : line
                // the result must hold one entry per source line, so the failable initializer has
                // no answer here: a malformed line has to survive as replacement characters
                let text = String(decoding: body, as: UTF8.self)  // sm:ignore useFailableStringInit
                return TerminalEscapes.stripped(text)
            }
    }
}
