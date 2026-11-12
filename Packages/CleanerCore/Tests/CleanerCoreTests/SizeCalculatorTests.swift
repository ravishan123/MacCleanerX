import Darwin
import Foundation
import Testing
@testable import CleanerCore

@Suite("SizeCalculator")
struct SizeCalculatorTests {
    private let mib = 1024 * 1024

    private func randomData(_ count: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 1...255, using: &g) })
    }

    @Test func measuresSingleFile() throws {
        let fx = try Fixture()
        try fx.file("a.bin", bytes: 100_000)
        let info = try #require(SizeCalculator.measure(fx.url("a.bin")))
        #expect(info.logicalBytes == 100_000)
        #expect(info.allocatedBytes >= 100_000)
        #expect(info.reclaimableBytes > 0)
        #expect(info.reclaimableBytes <= info.allocatedBytes)
        #expect(info.fileCount == 1)
        #expect(info.isComplete)
    }

    @Test func sumsNestedDirectory() throws {
        let fx = try Fixture()
        try fx.file("d/one", bytes: 65_536)
        try fx.file("d/sub/two", bytes: 65_536)
        try fx.file("d/sub/deeper/three", bytes: 65_536)
        let info = try #require(SizeCalculator.measure(fx.url("d")))
        #expect(info.logicalBytes == 3 * 65_536)
        #expect(info.fileCount == 3)
        #expect(info.reclaimableBytes >= 3 * 65_536)
    }

    @Test func sparseFileReportsAllocatedNotLogical() throws {
        let fx = try Fixture()
        let url = fx.url("sparse.img")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(50 * mib))
        try handle.write(contentsOf: Data([1]))
        try handle.close()

        let info = try #require(SizeCalculator.measure(url))
        #expect(info.logicalBytes == Int64(50 * mib + 1))
        #expect(info.allocatedBytes < Int64(mib))
        #expect(info.reclaimableBytes <= info.allocatedBytes)
    }

    @Test func hardLinksInsideItemAreCountedOnce() throws {
        let fx = try Fixture()
        try fx.file("d/a", bytes: mib)
        try FileManager.default.linkItem(at: fx.url("d/a"), to: fx.url("d/b"))

        let info = try #require(SizeCalculator.measure(fx.url("d")))
        #expect(info.fileCount == 2)
        #expect(info.logicalBytes == Int64(mib))
        #expect(info.allocatedBytes < Int64(2 * mib))
        #expect(info.reclaimableBytes >= Int64(mib))
    }

    @Test func hardLinkWithLinkOutsideIsNotReclaimable() throws {
        let fx = try Fixture()
        try fx.file("d/a", bytes: mib)
        try fx.dir("elsewhere")
        try FileManager.default.linkItem(at: fx.url("d/a"), to: fx.url("elsewhere/a"))

        let info = try #require(SizeCalculator.measure(fx.url("d")))
        #expect(info.allocatedBytes >= Int64(mib))
        #expect(info.reclaimableBytes == 0, "Deleting d/a frees nothing while elsewhere/a exists")
    }

    @Test func apfsCloneIsNotReportedAsReclaimable() throws {
        let fx = try Fixture()
        try fx.dir("d")
        try randomData(4 * mib).write(to: fx.url("d/original"))
        let cloned = clonefile(fx.path("d/original"), fx.path("d/clone"), 0)
        try #require(cloned == 0, "Fixture volume must support APFS clones")

        let clone = try #require(SizeCalculator.measure(fx.url("d/clone")))
        #expect(clone.allocatedBytes >= Int64(4 * mib))
        #expect(clone.reclaimableBytes < Int64(mib), "Clone shares its blocks with the original")

        // Conservative: shared blocks are never counted, even for the pair.
        let both = try #require(SizeCalculator.measure(fx.url("d")))
        #expect(both.reclaimableBytes < both.allocatedBytes)
    }

    @Test func privateSizeIsReportedForPlainFile() throws {
        let fx = try Fixture()
        try randomData(mib).write(to: fx.url("plain"))
        let privateSize = try #require(SizeCalculator.privateSize(fx.path("plain")))
        #expect(privateSize >= Int64(mib))
    }

    @Test func doesNotFollowSymlinks() throws {
        let fx = try Fixture()
        try fx.file("outside/big", bytes: 4 * mib)
        try fx.file("outside/dir/big2", bytes: 4 * mib)
        try fx.symlink("d/file-link", to: fx.path("outside/big"))
        try fx.symlink("d/dir-link", to: fx.path("outside/dir"))

        let info = try #require(SizeCalculator.measure(fx.url("d")))
        #expect(info.fileCount == 2)
        #expect(info.allocatedBytes == 0)
        #expect(info.reclaimableBytes == 0)
    }

    @Test func reportsNewestModificationInsideFolder() throws {
        let fx = try Fixture()
        try fx.file("d/old")
        try fx.file("d/sub/newer")
        let old = Date().addingTimeInterval(-2 * 86_400)
        let newer = Date().addingTimeInterval(-3_600)
        try fx.setModificationDate("d/old", old)
        try fx.setModificationDate("d/sub/newer", newer)
        try fx.setModificationDate("d/sub", old)
        try fx.setModificationDate("d", old)

        let info = try #require(SizeCalculator.measure(fx.url("d")))
        let newest = try #require(info.newestModification)
        #expect(abs(newest.timeIntervalSince(newer)) < 1)
    }

    @Test func missingItemReturnsNil() throws {
        let fx = try Fixture()
        #expect(SizeCalculator.measure(fx.url("nope")) == nil)
    }
}
