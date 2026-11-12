import Foundation
import Testing
@testable import CleanerCore

/// Layout used by most tests:
///
///     <fixture>/allowed/            ← the only allowlist root
///     <fixture>/allowed/a.txt
///     <fixture>/allowed/sub/b.txt
///     <fixture>/allowedEvil/c.txt   ← shares a name prefix, must be rejected
///     <fixture>/outside/secret.txt  ← must never be reachable
@Suite("SafetyGuard")
struct SafetyGuardTests {

    private func makeFixture() throws -> Fixture {
        let fx = try Fixture()
        try fx.file("allowed/a.txt")
        try fx.file("allowed/sub/b.txt")
        try fx.file("allowedEvil/c.txt")
        try fx.file("outside/secret.txt")
        return fx
    }

    private func makeGuard(_ fx: Fixture, roots: [String] = ["allowed"]) -> SafetyGuard {
        SafetyGuard(allowedRoots: roots.map { fx.url($0) })
    }

    private func expectRejection(
        _ expected: SafetyGuard.Rejection,
        _ g: SafetyGuard,
        path: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(throws: expected, sourceLocation: sourceLocation) {
            try g.validate(path: path)
        }
    }

    // MARK: Accepted paths

    @Test func acceptsFileAndDirectoryInsideAllowlist() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        #expect(try g.validate(fx.url("allowed/a.txt")).url.path == fx.path("allowed/a.txt"))
        #expect(try g.validate(fx.url("allowed/sub")).url.path == fx.path("allowed/sub"))
        #expect(try g.validate(fx.url("allowed/sub/b.txt")).isSymlink == false)
    }

    @Test func acceptsSymlinkThatStaysInsideAllowlist() throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/link", to: fx.path("allowed/sub/b.txt"))
        let v = try makeGuard(fx).validate(fx.url("allowed/link"))
        #expect(v.isSymlink)
        #expect(v.url.path == fx.path("allowed/link"))
    }

    @Test func returnsCanonicalPathForVarAlias() throws {
        let fx = try makeFixture()
        // Fixture lives in /private/var/folders/...; the /var alias must canonicalise.
        let aliased = fx.path("allowed/a.txt").replacingOccurrences(of: "/private/var/", with: "/var/")
        try #require(aliased.hasPrefix("/var/"))
        #expect(try makeGuard(fx).validate(path: aliased).url.path == fx.path("allowed/a.txt"))
    }

    // MARK: Allowlist boundaries

    @Test func rejectsAllowlistRootItself() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        expectRejection(.allowlistRoot, g, path: fx.path("allowed"))
        expectRejection(.allowlistRoot, g, path: fx.path("allowed") + "/")
        expectRejection(.allowlistRoot, g, path: fx.path("allowed/sub/.."))
    }

    @Test func rejectsSiblingFolderSharingNamePrefix() throws {
        let fx = try makeFixture()
        expectRejection(.outsideAllowlist, makeGuard(fx), path: fx.path("allowedEvil/c.txt"))
    }

    @Test func rejectsNestedRootAsRootButAllowsItsContents() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx, roots: ["allowed", "allowed/sub"])
        expectRejection(.allowlistRoot, g, path: fx.path("allowed/sub"))
        #expect(throws: Never.self) { try g.validate(fx.url("allowed/sub/b.txt")) }
    }

    // MARK: Path traversal

    @Test(arguments: [
        "allowed/../outside/secret.txt",
        "allowed/sub/../../outside/secret.txt",
        "allowed/./sub/./../../outside/secret.txt",
        "allowed/../allowedEvil/c.txt",
    ])
    func rejectsTraversalOutOfAllowlist(relative: String) throws {
        let fx = try makeFixture()
        // Build the raw string by hand so URL does not normalise it for us.
        let raw = fx.root.path(percentEncoded: false) + "/" + relative
        expectRejection(.outsideAllowlist, makeGuard(fx), path: raw)
    }

    @Test func rejectsTraversalAboveFilesystemRoot() throws {
        let fx = try makeFixture()
        expectRejection(.systemPath, makeGuard(fx), path: "/../../../System/Library")
        expectRejection(.systemPath, makeGuard(fx), path: "/..")
    }

    @Test func traversalThatStaysInsideIsCanonicalised() throws {
        let fx = try makeFixture()
        let raw = fx.root.path(percentEncoded: false) + "/allowed/sub/../a.txt"
        #expect(try makeGuard(fx).validate(path: raw).url.path == fx.path("allowed/a.txt"))
    }

    // MARK: Symlink escapes

    @Test func rejectsSymlinkToFileOutsideAllowlist() throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/escape", to: fx.path("outside/secret.txt"))
        expectRejection(.symlinkEscapesAllowlist, makeGuard(fx), path: fx.path("allowed/escape"))
    }

    @Test func rejectsRelativeSymlinkOutsideAllowlist() throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/escape", to: "../outside/secret.txt")
        expectRejection(.symlinkEscapesAllowlist, makeGuard(fx), path: fx.path("allowed/escape"))
    }

    @Test func rejectsPathThroughSymlinkedDirectory() throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/linkdir", to: fx.path("outside"))
        // The parent resolves to <fixture>/outside, so the file is outside.
        expectRejection(.outsideAllowlist, makeGuard(fx), path: fx.path("allowed/linkdir/secret.txt"))
        // The link itself is also refused because its target is outside.
        expectRejection(.symlinkEscapesAllowlist, makeGuard(fx), path: fx.path("allowed/linkdir"))
    }

    @Test(arguments: ["/System/Library", "/Library", "/usr/bin", "/"])
    func rejectsSymlinkToSystemLocation(target: String) throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/sys", to: target)
        expectRejection(.symlinkEscapesAllowlist, makeGuard(fx), path: fx.path("allowed/sys"))
    }

    @Test func rejectsSymlinkToHomeFolder() throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/home", to: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false))
        expectRejection(.symlinkEscapesAllowlist, makeGuard(fx), path: fx.path("allowed/home"))
    }

    @Test func rejectsSymlinkToAllowlistRoot() throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/self", to: fx.path("allowed"))
        expectRejection(.symlinkEscapesAllowlist, makeGuard(fx), path: fx.path("allowed/self"))
    }

    @Test func rejectsBrokenSymlink() throws {
        let fx = try makeFixture()
        try fx.symlink("allowed/dangling", to: fx.path("allowed/does-not-exist"))
        expectRejection(.brokenSymlink, makeGuard(fx), path: fx.path("allowed/dangling"))
    }

    // MARK: Home folder

    @Test func rejectsRealHomeFolderRoot() throws {
        let fx = try makeFixture()
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let g = makeGuard(fx)
        expectRejection(.homeFolder, g, path: home)
        expectRejection(.homeFolder, g, path: home + "/")
        expectRejection(.homeFolder, g, path: home + "/Library/..")
        expectRejection(.homeFolder, g, path: home.uppercased())
    }

    @Test func rejectsAncestorsOfHomeFolder() throws {
        let fx = try makeFixture()
        let parent = FileManager.default.homeDirectoryForCurrentUser.deletingLastPathComponent().path(percentEncoded: false)
        expectRejection(.ancestorOfHome, makeGuard(fx), path: parent)
    }

    @Test func homeFolderCannotBeAllowlisted() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let g = SafetyGuard(allowedRoots: [home])
        #expect(g.allowedRoots.isEmpty)
        #expect(g.droppedRoots == [home])
        expectRejection(.homeFolder, g, path: home.path(percentEncoded: false))
    }

    @Test func rejectsInjectedHomeEvenWhenInsideAllowlist() throws {
        let fx = try makeFixture()
        try fx.file("allowed/home/Documents/thesis.txt")
        let g = SafetyGuard(allowedRoots: [fx.url("allowed")], home: fx.url("allowed/home"))
        expectRejection(.homeFolder, g, path: fx.path("allowed/home"))
        // Contents of a fake home inside the allowlist are fine; it is only a fixture.
        #expect(throws: Never.self) { try g.validate(fx.url("allowed/home/Documents/thesis.txt")) }
    }

    // MARK: System locations

    @Test(arguments: [
        "/System",
        "/System/Library",
        "/System/Library/CoreServices/Finder.app",
        "/SYSTEM/library",
    ])
    func rejectsSystem(path: String) throws {
        let fx = try makeFixture()
        expectRejection(.systemPath, makeGuard(fx), path: path)
    }

    @Test(arguments: [
        "/Library",
        "/Library/Caches",
        "/Library/LaunchDaemons",
        "/library/caches",
    ])
    func rejectsLibrary(path: String) throws {
        let fx = try makeFixture()
        expectRejection(.systemPath, makeGuard(fx), path: path)
    }

    @Test(arguments: [
        "/usr/bin/true", "/bin/ls", "/sbin", "/Applications", "/etc/hosts",
        "/private/etc/hosts", "/tmp", "/private/tmp", "/private/var/db",
        "/var/log", "/opt", "/Volumes", "/Users/Shared",
    ])
    func rejectsOtherSystemLocations(path: String) throws {
        let fx = try makeFixture()
        expectRejection(.systemPath, makeGuard(fx), path: path)
    }

    @Test func systemLocationsCannotBeAllowlisted() throws {
        let roots = ["/System/Library", "/Library/Caches", "/usr", "/private/tmp", "/Applications"]
            .map { URL(fileURLWithPath: $0) }
        let g = SafetyGuard(allowedRoots: roots)
        #expect(g.allowedRoots.isEmpty)
        #expect(g.droppedRoots.count == roots.count)
        expectRejection(.systemPath, g, path: "/Library/Caches/com.apple.something")
        expectRejection(.systemPath, g, path: "/System/Library/Caches")
    }

    @Test func userTemporaryDirectoryIsTheOnlyPrivateExemption() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        // Fixture lives under /private/var/folders/.../T and is accepted…
        #expect(fx.root.path.hasPrefix("/private/var/folders/"))
        #expect(throws: Never.self) { try g.validate(fx.url("allowed/a.txt")) }
        // …but its parent folders (still /private/var/folders/…) are not.
        let tParent = fx.root.deletingLastPathComponent().deletingLastPathComponent().path(percentEncoded: false)
        expectRejection(.systemPath, g, path: tParent)
    }

    @Test func detectsSIPRestrictedFlag() throws {
        let fx = try makeFixture()
        #expect(SafetyGuard.isSIPProtected(URL(fileURLWithPath: "/bin/ls")))
        #expect(SafetyGuard.isSIPProtected(URL(fileURLWithPath: "/usr/bin")))
        #expect(!SafetyGuard.isSIPProtected(fx.url("allowed/a.txt")))
    }

    // MARK: Empty / invalid allowlists

    @Test func emptyAllowlistRejectsEverything() throws {
        let fx = try makeFixture()
        let g = SafetyGuard(allowedRoots: [])
        expectRejection(.emptyAllowlist, g, path: fx.path("allowed/a.txt"))
        expectRejection(.emptyAllowlist, g, path: fx.path("outside/secret.txt"))
        // System and home rules still win over "empty".
        expectRejection(.systemPath, g, path: "/System")
        expectRejection(.homeFolder, g, path: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false))
    }

    @Test func allowlistOfOnlyInvalidRootsBehavesAsEmpty() throws {
        let fx = try makeFixture()
        let g = SafetyGuard(allowedRoots: [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: "/usr/local"),
            fx.url("missing-root"),
            URL(string: "https://example.com/cache")!,
        ])
        #expect(g.allowedRoots.isEmpty)
        #expect(g.droppedRoots.count == 5)
        expectRejection(.emptyAllowlist, g, path: fx.path("allowed/a.txt"))
    }

    // MARK: Malformed input

    @Test func rejectsMalformedInput() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        expectRejection(.relativePath, g, path: "allowed/a.txt")
        expectRejection(.relativePath, g, path: "../etc/hosts")
        expectRejection(.relativePath, g, path: "")
        expectRejection(.invalidPath, g, path: fx.path("allowed/a.txt") + "\0/../../outside")
        #expect(throws: SafetyGuard.Rejection.notAFileURL) {
            try g.validate(URL(string: "https://example.com/allowed/a.txt")!)
        }
    }

    @Test func rejectsMissingItemsAndParents() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        expectRejection(.doesNotExist, g, path: fx.path("allowed/nope.txt"))
        expectRejection(.parentUnresolvable, g, path: fx.path("allowed/nope/deeper.txt"))
    }

    // MARK: Time-of-check / time-of-use

    @Test func revalidateCatchesFileSwappedForEscapingSymlink() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        let scanned = try g.validate(fx.url("allowed/a.txt"))
        // Simulate an attacker (or app) replacing the file after the scan.
        try FileManager.default.removeItem(at: fx.url("allowed/a.txt"))
        try fx.symlink("allowed/a.txt", to: fx.path("outside/secret.txt"))
        #expect(throws: SafetyGuard.Rejection.symlinkEscapesAllowlist) { try g.revalidate(scanned) }
    }

    @Test func revalidateCatchesFileReplacedByDifferentFile() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        let scanned = try g.validate(fx.url("allowed/a.txt"))
        try FileManager.default.removeItem(at: fx.url("allowed/a.txt"))
        try fx.file("outside/decoy.txt") // keep the old inode number from being reused
        try fx.file("allowed/a.txt")
        #expect(throws: SafetyGuard.Rejection.identityChanged) { try g.revalidate(scanned) }
    }

    @Test func revalidateAcceptsUnchangedItem() throws {
        let fx = try makeFixture()
        let g = makeGuard(fx)
        let scanned = try g.validate(fx.url("allowed/sub/b.txt"))
        #expect(try g.revalidate(scanned) == scanned)
    }
}
