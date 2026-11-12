import Foundation

/// A throwaway folder under the user's temporary directory. Every test that
/// touches the file system works inside one of these, never in real user
/// folders. On deinit it removes only the folder it created.
final class Fixture {
    static let prefix = "MacCleanerTests-"

    /// Canonical (realpath) URL of the fixture folder.
    let root: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
        let raw = tmp.appending(path: Self.prefix + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: false)
        guard let resolved = Darwin.realpath(raw.path(percentEncoded: false), nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(resolved) }
        root = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    deinit {
        // Only ever delete our own uniquely named folder inside $TMPDIR.
        guard let tmp = Darwin.realpath(FileManager.default.temporaryDirectory.path(percentEncoded: false), nil) else { return }
        defer { free(tmp) }
        let tmpPath = String(cString: tmp)
        let path = root.path(percentEncoded: false)
        guard path.hasPrefix(tmpPath + "/" + Self.prefix),
              root.deletingLastPathComponent().path(percentEncoded: false) == tmpPath
                || root.deletingLastPathComponent().path(percentEncoded: false) == tmpPath + "/"
        else { return }
        // FileManager.removeItem does not follow symlinks inside the folder.
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ relative: String) -> URL {
        root.appending(path: relative)
    }

    func path(_ relative: String) -> String {
        url(relative).path(percentEncoded: false)
    }

    @discardableResult
    func dir(_ relative: String) throws -> URL {
        let u = url(relative)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    func file(_ relative: String, bytes: Int = 16) throws -> URL {
        let u = url(relative)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: u)
        return u
    }

    @discardableResult
    func symlink(_ relative: String, to destination: String) throws -> URL {
        let u = url(relative)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: u.path(percentEncoded: false), withDestinationPath: destination)
        return u
    }
}
