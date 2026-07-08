import MCP
import Darwin
import Foundation

/// Errors raised while durably writing an Xcode project file.
public enum SafeProjectWriteError: Error, CustomStringConvertible, LocalizedError,
    MCPErrorConvertible
{
    /// The on-disk file changed between the caller's read and this write (optimistic concurrency
    /// guard tripped). The write was refused and the file left untouched.
    case concurrentModification(path: String)
    /// The candidate file failed validation (e.g. `plutil -lint`). The original file was left
    /// untouched.
    case validationFailed(path: String, detail: String)
    /// A filesystem operation (lock, temp write, fsync, rename) failed. The original file was left
    /// untouched.
    case ioFailed(path: String, detail: String)

    public var description: String {
        switch self {
            case let .concurrentModification(path):
                "Project file was modified by another writer since it was read "
                    + "(\(path)). The edit was refused to avoid clobbering that change — "
                    + "re-run the operation against the current project."
            case let .validationFailed(path, detail):
                "Refusing to write an invalid project file (\(path)): \(detail). "
                    + "The original file was left unchanged."
            case let .ioFailed(path, detail):
                "Failed to write project file \(path): \(detail). "
                    + "The original file was left unchanged."
        }
    }

    public var errorDescription: String? { description }

    public func toMCPError() -> MCPError {
        switch self {
            case .concurrentModification: .invalidParams(description)
            case .validationFailed, .ioFailed: .internalError(description)
        }
    }
}

/// Durable, atomic, serialized writer for Xcode project files (`project.pbxproj`).
///
/// Every mutation funnels through here so a crash, a kill, an invalid serialization, or a
/// concurrent writer can never corrupt or silently clobber the shared project file. The guarantees:
///
/// 1. **Atomic.** The new bytes are written to a temp file in the same directory, `fsync`'d, then
///    `rename(2)`'d over the original. A crash at any point leaves the original byte-for-byte
///    intact (the original is never opened for writing).
/// 2. **Validated.** The candidate is checked with `plutil -lint` *before* it replaces the
///    original. An invalid project is rejected and the original is left untouched — there is
///    nothing to roll back because the original is only swapped in after validation passes.
/// 3. **Serialized.** An advisory `flock` on a per-project lock file makes the read-compare-rename
///    window mutually exclusive, so concurrent tool calls queue instead of racing.
/// 4. **Concurrency-guarded.** When the caller passes the bytes it read, this re-reads the file
///    under the lock and refuses the write if they differ — the other writer's change is preserved
///    and the caller is told to re-run.
public enum SafeProjectWrite {
    /// Atomically and durably write `data` to `destination`, serialized by an advisory lock, with
    /// validation and an optional optimistic-concurrency guard.
    ///
    /// - Parameters:
    ///   - data: The complete new file contents.
    ///   - destination: Absolute path to the file to replace (e.g.
    ///     `…/Foo.xcodeproj/project.pbxproj`).
    ///   - lockIdentifier: A stable identifier for the resource being written (typically the
    ///     `.xcodeproj` bundle path). Concurrent writes sharing an identifier serialize.
    ///   - expectedPreimage: If non-nil, the current on-disk bytes must equal this or the write is
    ///     refused with ``SafeProjectWriteError/concurrentModification(path:)``. Pass the bytes
    ///     read at load time to guard against clobbering a concurrent edit. Pass `nil` to skip the
    ///     guard (e.g. when creating a new file).
    ///   - validate: Whether to run `plutil -lint` on the candidate before promoting it. Defaults
    ///     to `true`.
    public static func write(
        _ data: Data,
        to destination: String,
        lockIdentifier: String,
        expectedPreimage: Data? = nil,
        validate: Bool = true,
    ) throws(SafeProjectWriteError) {
        let lockFD = acquireLock(for: lockIdentifier)

        defer {
            if lockFD >= 0 {
                flock(lockFD, LOCK_UN)
                close(lockFD)
            }
        }

        // Optimistic concurrency guard: under the lock, confirm the file is still what the caller
        // read. If another writer committed in the meantime, refuse rather than clobber.
        if let expectedPreimage {
            let current = FileManager.default.contents(atPath: destination) ?? Data()
            guard current == expectedPreimage else {
                throw .concurrentModification(path: destination)
            }
        }

        let dir = (destination as NSString).deletingLastPathComponent
        let tmpPath = try writeTempFile(data, inDirectory: dir, destination: destination)

        // From here on, ensure the temp file never lingers on an error path.
        var promoted = false
        defer { if !promoted { unlink(tmpPath) } }

        if validate { try lint(tmpPath, finalPath: destination) }

        // Referential-integrity gate: refuse a project write that *introduces* a dangling object
        // reference (a UUID pointing at an object that no longer exists). `plutil -lint` passes
        // such a file because it is still a valid plist; Xcode, however, fails to load it. Diffed
        // against the current on-disk bytes so an already-broken project can still be repaired.
        if validate, PBXProjReferenceAudit.isProjectFile(destination) {
            let baseline = FileManager.default.contents(atPath: destination)
            let introduced = PBXProjReferenceAudit.newDanglingReferences(
                candidate: data, baseline: baseline)
            guard introduced.isEmpty else {
                throw .validationFailed(
                    path: destination,
                    detail: "write would introduce dangling object reference(s) "
                        + introduced.sorted().joined(separator: ", ")
                        + " — refusing to write a project Xcode could not load")
            }
        }

        preservePermissions(from: destination, to: tmpPath)

        guard rename(tmpPath, destination) == 0 else {
            throw .ioFailed(path: destination, detail: "atomic rename failed: \(errnoString())")
        }
        promoted = true

        fsyncDirectory(dir)
    }

    // MARK: - Locking

    /// Open (creating if needed) and exclusively `flock` a per-project lock file in the temp
    /// directory. Returns -1 if the lock could not be taken; the write then proceeds unserialized
    /// rather than failing (the atomic rename still prevents torn files).
    private static func acquireLock(for identifier: String) -> Int32 {
        let lockPath = lockFilePath(for: identifier)
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return -1 }
        guard flock(fd, LOCK_EX) == 0 else {
            close(fd)
            return -1
        }
        return fd
    }

    private static func lockFilePath(for identifier: String) -> String {
        // A stable, filesystem-safe name derived from the resource path. Kept in the temp directory
        // so it never pollutes the project's working tree.
        let hash = fnv1a(identifier)
        let tmp = NSTemporaryDirectory()
        return (tmp as NSString).appendingPathComponent("xc-mcp-pbxproj-\(hash).lock")
    }

    /// FNV-1a 64-bit hash, rendered as hex. Deterministic across processes (unlike `Hashable`), so
    /// two processes editing the same project derive the same lock file.
    private static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325

        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return .init(hash, radix: 16)
    }

    // MARK: - Atomic write

    private static func writeTempFile(
        _ data: Data,
        inDirectory dir: String,
        destination: String,
    ) throws(SafeProjectWriteError) -> String {
        let template = (dir as NSString).appendingPathComponent(".xc-mcp-write-XXXXXX")
        var templateBytes = Array(template.utf8CString)
        let fd = mkstemp(&templateBytes)
        guard fd >= 0 else {
            throw .ioFailed(
                path: destination, detail: "could not create temp file: \(errnoString())")
        }
        let tmpPath = templateBytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }

        var writeError: SafeProjectWriteError?
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            let total = raw.count
            let base = raw.baseAddress
            while offset < total {
                let written = Darwin.write(fd, base?.advanced(by: offset), total - offset)

                if written < 0 {
                    if errno == EINTR { continue }
                    writeError = .ioFailed(
                        path: destination, detail: "write failed: \(errnoString())")
                    return
                }
                offset += written
            }
        }

        if writeError == nil, fsync(fd) != 0 {
            writeError = .ioFailed(path: destination, detail: "fsync failed: \(errnoString())")
        }
        close(fd)

        if let writeError {
            unlink(tmpPath)
            throw writeError
        }
        return tmpPath
    }

    /// Copy the original file's POSIX permissions onto the temp file so the atomic rename preserves
    /// the project's mode bits (mkstemp creates 0600).
    private static func preservePermissions(from original: String, to tmpPath: String) {
        var st = stat()
        if stat(original, &st) == 0 { chmod(tmpPath, st.st_mode & 0o7777) }
    }

    /// `fsync` the containing directory so the rename itself is durable across a crash.
    private static func fsyncDirectory(_ dir: String) {
        let dfd = open(dir, O_RDONLY)

        if dfd >= 0 {
            fsync(dfd)
            close(dfd)
        }
    }

    // MARK: - Validation

    private static func lint(
        _ candidatePath: String,
        finalPath: String,
    ) throws(SafeProjectWriteError) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-lint", candidatePath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            // plutil unavailable — skip validation rather than block the write.
            return
        }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        // Lossy decode: plutil's diagnostic text is informational, never fail on stray bytes.
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self,  // sm:ignore useFailableStringInit
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        throw .validationFailed(
            path: finalPath,
            detail: output.isEmpty
                ? "plutil -lint failed"
                : output)
    }

    private static func errnoString() -> String { .init(cString: strerror(errno)) }
}
