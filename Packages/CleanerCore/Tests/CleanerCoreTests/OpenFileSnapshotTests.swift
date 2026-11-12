import Foundation
import Testing
@testable import CleanerCore

@Suite("OpenFileSnapshot")
struct OpenFileSnapshotTests {

    @Test func detectsFileOpenedByThisProcess() throws {
        let fx = try Fixture()
        try fx.file("d/open.txt")
        try fx.file("d/closed.txt")
        try fx.file("other/x.txt")

        let handle = try FileHandle(forReadingFrom: fx.url("d/open.txt"))
        defer { try? handle.close() }

        let snapshot = OpenFileSnapshot.capture()
        #expect(snapshot.isInUse(fx.url("d/open.txt")))
        #expect(snapshot.isInUse(fx.url("d")), "A folder is in use if anything inside is open")
        #expect(!snapshot.isInUse(fx.url("d/closed.txt")))
        #expect(!snapshot.isInUse(fx.url("other")))
    }

    @Test func detectsWorkingDirectory() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let resolved = try #require(SafetyGuard.realpath(cwd))
        #expect(OpenFileSnapshot.capture().isInUse(URL(fileURLWithPath: resolved)))
    }

    @Test func prefixMatchingRespectsPathBoundaries() {
        let s = OpenFileSnapshot(paths: ["/a/b-c/file", "/a/bc", "/a/b0/x"])
        #expect(!s.isInUse(URL(fileURLWithPath: "/a/b")))

        let t = OpenFileSnapshot(paths: ["/a/b-c/file", "/a/b/deep/file"])
        #expect(t.isInUse(URL(fileURLWithPath: "/a/b")))
        #expect(t.isInUse(URL(fileURLWithPath: "/a/b/")))
        #expect(t.isInUse(URL(fileURLWithPath: "/a/b/deep/file")))
        #expect(!t.isInUse(URL(fileURLWithPath: "/a/b/deep/fil")))
        #expect(!OpenFileSnapshot.empty.isInUse(URL(fileURLWithPath: "/a")))
    }
}
