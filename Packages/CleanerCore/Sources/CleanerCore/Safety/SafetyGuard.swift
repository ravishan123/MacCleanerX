import Darwin
import Foundation

/// The last line of defence before anything is removed.
///
/// Every path must pass `validate` (at scan time) and `revalidate`
/// (immediately before removal). Callers must act on the returned
/// `ValidatedPath.url`, which is the canonical path that was actually checked,
/// never on the raw input.
///
/// Rules, in order:
/// 1. Only absolute `file://` paths. `.` and `..` are removed lexically.
/// 2. The parent folder is resolved with `realpath(3)` so a symlinked
///    directory anywhere in the path cannot redirect us.
/// 3. System locations (`/System`, `/Library`, `/usr`, `/private`, …) are
///    always rejected, except inside the user's own temporary directory.
/// 4. The home folder and its ancestors are always rejected.
/// 5. The path must be strictly inside an allowlisted root (never the root
///    itself). Allowlisted roots must themselves be inside the home folder or
///    the user's temporary directory; anything else is dropped at init.
/// 6. The item must exist, must not carry the SIP `restricted` flag or an
///    immutable/append-only flag, and must be on the same volume as its root.
/// 7. If the item is a symlink, its fully resolved target must also satisfy
///    rules 3–5; broken symlinks are rejected.
public struct SafetyGuard: Sendable {

    public enum Rejection: Error, Sendable, Equatable, CustomStringConvertible {
        case notAFileURL
        case relativePath
        case invalidPath
        case parentUnresolvable
        case systemPath
        case homeFolder
        case ancestorOfHome
        case emptyAllowlist
        case allowlistRoot
        case outsideAllowlist
        case doesNotExist
        case sipProtected
        case immutable
        case crossesVolume
        case symlinkEscapesAllowlist
        case brokenSymlink
        case identityChanged

        public var description: String {
            switch self {
            case .notAFileURL: "Not a file URL"
            case .relativePath: "Path is not absolute"
            case .invalidPath: "Path contains invalid characters"
            case .parentUnresolvable: "Parent folder could not be resolved"
            case .systemPath: "System location"
            case .homeFolder: "Home folder"
            case .ancestorOfHome: "Folder that contains the home folder"
            case .emptyAllowlist: "No cleanable locations are configured"
            case .allowlistRoot: "Top-level cleanable folder itself"
            case .outsideAllowlist: "Outside the cleanable locations"
            case .doesNotExist: "Item no longer exists"
            case .sipProtected: "Protected by System Integrity Protection"
            case .immutable: "Item is locked"
            case .crossesVolume: "Item is on a different volume"
            case .symlinkEscapesAllowlist: "Symbolic link points outside the cleanable locations"
            case .brokenSymlink: "Symbolic link target is missing"
            case .identityChanged: "Item changed since it was scanned"
            }
        }
    }

    /// A path that passed validation, with the identity it had at that moment.
    public struct ValidatedPath: Sendable, Hashable {
        /// Canonical path that was checked. Act on this, not on the input.
        public let url: URL
        public let device: Int64
        public let inode: UInt64
        public let isSymlink: Bool
    }

    /// Hard-blocked top-level locations (compared case-insensitively).
    public static let protectedPrefixes: [String] = [
        "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
        "/private", "/etc", "/var", "/tmp", "/opt", "/cores", "/dev",
        "/Volumes", "/Network", "/Users/Shared",
    ]

    /// Effective, canonical allowlist roots.
    public let allowedRoots: [URL]
    /// Roots that were passed in but refused (missing, system, or outside
    /// the home/temporary folders).
    public let droppedRoots: [URL]

    private let rootComponents: [[String]]
    private let homeComponents: [String]
    private let exemptComponents: [[String]]
    private let protectedComponents: [[String]]

    /// - Parameters:
    ///   - allowedRoots: Folders whose *contents* may be cleaned.
    ///   - home: The user's home folder (injectable for tests).
    ///   - systemExemptions: Locations under a protected prefix that roots may
    ///     still live in. Defaults to the user's own `$TMPDIR`.
    public init(
        allowedRoots: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemExemptions: [URL] = [FileManager.default.temporaryDirectory]
    ) {
        let homePath = Self.realpath(home.path(percentEncoded: false)) ?? home.standardizedFileURL.path(percentEncoded: false)
        let homeComponents = Self.components(homePath)
        let exempt = systemExemptions
            .compactMap { Self.realpath($0.path(percentEncoded: false)) }
            .map(Self.components)
            .filter { !$0.isEmpty }
        let protected = Self.protectedPrefixes.map { Self.components($0.lowercased()) }

        var kept: [[String]] = []
        var dropped: [URL] = []
        for root in allowedRoots {
            guard root.isFileURL,
                  let resolved = Self.realpath(root.path(percentEncoded: false))
            else {
                dropped.append(root)
                continue
            }
            let c = Self.components(resolved)
            let insideHome = Self.isStrictDescendant(c, of: homeComponents, caseInsensitive: true)
            let insideExempt = exempt.contains { $0 == c || Self.isStrictDescendant(c, of: $0) }
            let blocked = Self.isProtected(c, protected: protected, exempt: exempt)
            if (insideHome || insideExempt) && !blocked {
                if !kept.contains(c) { kept.append(c) }
            } else {
                dropped.append(root)
            }
        }

        self.homeComponents = homeComponents
        self.exemptComponents = exempt
        self.protectedComponents = protected
        self.rootComponents = kept
        self.allowedRoots = kept.map { URL(fileURLWithPath: Self.join($0), isDirectory: true) }
        self.droppedRoots = dropped
    }

    // MARK: - Validation

    public func validate(_ url: URL) throws(Rejection) -> ValidatedPath {
        guard url.isFileURL else { throw .notAFileURL }
        return try validate(path: url.path(percentEncoded: false))
    }

    public func validate(path rawPath: String) throws(Rejection) -> ValidatedPath {
        guard rawPath.hasPrefix("/") else { throw .relativePath }
        guard !rawPath.contains("\0") else { throw .invalidPath }

        // 1. Lexical normalisation: drop "." and resolve "..".
        let lexical = Self.lexicallyNormalized(rawPath)
        guard let name = lexical.last else { throw .systemPath } // "/" itself

        // 2. Resolve the parent so symlinked directories can't redirect us.
        let parentPath = "/" + lexical.dropLast().joined(separator: "/")
        guard let resolvedParent = Self.realpath(parentPath) else { throw .parentUnresolvable }
        let components = Self.components(resolvedParent) + [name]
        let fullPath = Self.join(components)

        // 3–5. Location rules on the canonical path.
        let rootIndex = try checkLocation(components)

        // 6. Inspect the item itself without following a final symlink.
        var info = stat()
        guard lstat(fullPath, &info) == 0 else { throw .doesNotExist }
        if info.st_flags & Self.sipFlag != 0 { throw .sipProtected }
        if info.st_flags & Self.lockedFlags != 0 { throw .immutable }

        var rootInfo = stat()
        guard lstat(Self.join(rootComponents[rootIndex]), &rootInfo) == 0 else { throw .parentUnresolvable }
        guard rootInfo.st_dev == info.st_dev else { throw .crossesVolume }

        // 7. Symlinks: the target must be cleanable too.
        let isSymlink = (info.st_mode & S_IFMT) == S_IFLNK
        if isSymlink {
            guard let target = Self.realpath(fullPath) else { throw .brokenSymlink }
            do {
                _ = try checkLocation(Self.components(target))
            } catch {
                throw .symlinkEscapesAllowlist
            }
        }

        return ValidatedPath(
            url: URL(fileURLWithPath: fullPath),
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            isSymlink: isSymlink
        )
    }

    /// Re-run every check right before removal and confirm the item is still
    /// the same file (catches a file swapped for a symlink after the scan).
    public func revalidate(_ validated: ValidatedPath) throws(Rejection) -> ValidatedPath {
        let fresh = try validate(validated.url)
        guard fresh.device == validated.device,
              fresh.inode == validated.inode,
              fresh.isSymlink == validated.isSymlink
        else { throw .identityChanged }
        return fresh
    }

    /// True when the item carries the SIP `restricted` flag.
    public static func isSIPProtected(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
        return info.st_flags & sipFlag != 0
    }

    // MARK: - Location rules

    /// Returns the index of the allowlist root that contains `components`.
    private func checkLocation(_ components: [String]) throws(Rejection) -> Int {
        guard !components.isEmpty else { throw .systemPath }
        if Self.isProtected(components, protected: protectedComponents, exempt: exemptComponents) {
            throw .systemPath
        }
        if Self.equalIgnoringCase(components, homeComponents) { throw .homeFolder }
        if Self.isStrictDescendant(homeComponents, of: components, caseInsensitive: true) {
            throw .ancestorOfHome
        }
        guard !rootComponents.isEmpty else { throw .emptyAllowlist }
        if rootComponents.contains(where: { $0 == components }) { throw .allowlistRoot }
        if let index = rootComponents.firstIndex(where: { Self.isStrictDescendant(components, of: $0) }) {
            return index
        }
        throw .outsideAllowlist
    }

    private static func isProtected(_ c: [String], protected: [[String]], exempt: [[String]]) -> Bool {
        if exempt.contains(where: { $0 == c || isStrictDescendant(c, of: $0) }) { return false }
        let lower = c.map { $0.lowercased() }
        return protected.contains { p in lower.count >= p.count && Array(lower.prefix(p.count)) == p }
    }

    // MARK: - Path helpers

    private static let sipFlag = UInt32(SF_RESTRICTED)
    private static let lockedFlags = UInt32(SF_IMMUTABLE) | UInt32(UF_IMMUTABLE) | UInt32(SF_APPEND) | UInt32(UF_APPEND)

    static func realpath(_ path: String) -> String? {
        guard let resolved = Darwin.realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    static func join(_ components: [String]) -> String {
        "/" + components.joined(separator: "/")
    }

    static func lexicallyNormalized(_ path: String) -> [String] {
        var out: [String] = []
        for part in components(path) {
            switch part {
            case ".": continue
            case "..": if !out.isEmpty { out.removeLast() }
            default: out.append(part)
            }
        }
        return out
    }

    static func isStrictDescendant(_ c: [String], of ancestor: [String], caseInsensitive: Bool = false) -> Bool {
        guard c.count > ancestor.count else { return false }
        let prefix = Array(c.prefix(ancestor.count))
        return caseInsensitive ? equalIgnoringCase(prefix, ancestor) : prefix == ancestor
    }

    static func equalIgnoringCase(_ a: [String], _ b: [String]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
    }
}
