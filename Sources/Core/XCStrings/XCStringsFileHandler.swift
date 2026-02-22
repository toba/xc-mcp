import Foundation

/// Handles file I/O operations for xcstrings files
public struct XCStringsFileHandler: Sendable {
    private let path: String

    public init(path: String) {
        self.path = path
    }

    /// Load xcstrings file from disk
    public func load() throws(XCStringsError) -> XCStringsFile {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCStringsError.fileNotFound(path: path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XCStringsError.invalidFileFormat(path: path, reason: error.localizedDescription)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(XCStringsFile.self, from: data)
        } catch {
            throw XCStringsError.invalidFileFormat(path: path, reason: error.localizedDescription)
        }
    }

    /// Save xcstrings file to disk
    public func save(_ file: XCStringsFile) throws(XCStringsError) {
        let url = URL(fileURLWithPath: path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(file)
        } catch {
            throw XCStringsError.writeError(path: path, reason: error.localizedDescription)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw XCStringsError.writeError(path: path, reason: error.localizedDescription)
        }
    }

    /// Create a new xcstrings file
    public func create(sourceLanguage: String, overwrite: Bool = false) throws(XCStringsError) {
        let url = URL(fileURLWithPath: path)

        if !overwrite, FileManager.default.fileExists(atPath: path) {
            throw XCStringsError.fileAlreadyExists(path: path)
        }

        // Create parent directory if it doesn't exist
        let parentDir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let file = XCStringsFile(sourceLanguage: sourceLanguage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(file)
        } catch {
            throw XCStringsError.writeError(path: path, reason: error.localizedDescription)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw XCStringsError.writeError(path: path, reason: error.localizedDescription)
        }
    }
}
