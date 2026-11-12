import Darwin
import Foundation
@testable import CleanerCore

/// Records every call to the fake file operations.
final class OperationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock(); defer { lock.unlock() }
        entries.append(entry)
    }

    var calls: [String] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}

/// A command runner that records invocations and returns canned output.
final class FakeCommands: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations: [[String]] = []
    private let responses: [String: CommandOutput]

    /// `responses` is keyed by the space-joined arguments.
    init(_ responses: [String: CommandOutput] = [:]) {
        self.responses = responses
    }

    var calls: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return invocations
    }

    var runner: CommandRunner {
        CommandRunner { executable, arguments in
            self.lock.withLock { self.invocations.append([executable] + arguments) }
            return self.responses[arguments.joined(separator: " ")] ?? CommandOutput(status: 1, stdout: Data())
        }
    }
}

struct FixtureError: Error, CustomStringConvertible {
    let description: String
}

extension Fixture {
    /// File operations that never leave the fixture: "Trash" is
    /// `<fixture>/FakeTrash`, and permanent deletion refuses any path outside
    /// the fixture folder.
    func fakeOperations(log: OperationLog) -> FileOperations {
        // `.path` (not `path(percentEncoded:)`) so there is no trailing slash.
        let root = self.root.path
        let fakeTrash = self.url("FakeTrash")
        @Sendable func requireInside(_ url: URL) throws {
            guard url.path(percentEncoded: false).hasPrefix(root + "/") else {
                throw FixtureError(description: "Refusing to touch \(url.path) outside fixture")
            }
        }
        return FileOperations(
            moveToTrash: { url in
                try requireInside(url)
                try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
                let destination = fakeTrash.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                log.record("trash \(url.path(percentEncoded: false))")
                return destination
            },
            deletePermanently: { url in
                try requireInside(url)
                try FileManager.default.removeItem(at: url)
                log.record("delete \(url.path(percentEncoded: false))")
            }
        )
    }

    /// A context rooted entirely in the fixture.
    /// - Parameter clockOffset: How far "now" is ahead of the real clock.
    ///   The default of one hour makes freshly created fixture files look old
    ///   enough to clean; pass 0 to test the 10-minute rule.
    func context(
        log: OperationLog = OperationLog(),
        clockOffset: TimeInterval = 3600,
        commandRunner: CommandRunner = .unavailable,
        exclusions: [URL] = [],
        openFiles: @escaping @Sendable () -> OpenFileSnapshot = { OpenFileSnapshot.capture() }
    ) -> ModuleContext {
        ModuleContext(
            home: url("home"),
            temporaryDirectory: url("tmp"),
            operations: fakeOperations(log: log),
            commandRunner: commandRunner,
            openFiles: openFiles,
            now: { Date().addingTimeInterval(clockOffset) },
            exclusions: exclusions
        )
    }

    /// Path → (type, size, mtime) for everything under the fixture, used to
    /// prove that scans and dry runs change nothing.
    func treeSnapshot() -> [String: String] {
        var result: [String: String] = [:]
        let rootPath = root.path(percentEncoded: false)
        guard let e = FileManager.default.enumerator(atPath: rootPath) else { return result }
        while let rel = e.nextObject() as? String {
            var st = stat()
            guard lstat(rootPath + "/" + rel, &st) == 0 else { continue }
            result[rel] = "\(st.st_mode & S_IFMT) \(st.st_size) \(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec) \(st.st_ino)"
        }
        return result
    }

    func exists(_ relative: String) -> Bool {
        var st = stat()
        return lstat(path(relative), &st) == 0
    }

    func setModificationDate(_ relative: String, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path(relative))
    }
}
