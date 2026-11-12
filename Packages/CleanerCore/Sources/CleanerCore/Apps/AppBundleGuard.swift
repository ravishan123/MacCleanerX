import Darwin
import Foundation

/// The only exception to "never touch /Applications". It allows exactly one
/// thing: moving a whole `.app` bundle to the Trash, and only when
///
/// - it sits directly in an Applications folder (or one folder down),
/// - it is a real folder, not a symlink, and you own it,
/// - you can write to the folder that contains it,
/// - it is not signed by Apple and not from the Mac App Store,
/// - it is not running, not SIP-protected and not Mac Cleaner itself.
public struct AppBundleGuard: Sendable {
    public enum Rejection: Error, Sendable, Equatable, CustomStringConvertible {
        case notAnApp, notInApplicationsFolder, symlink, doesNotExist, notOwnedByYou, folderNotWritable
        case appleApp, appStoreApp, running, protectedApp, sipProtected, identityChanged

        public var description: String {
            switch self {
            case .notAnApp: "Not an app"
            case .notInApplicationsFolder: "Not in an Applications folder"
            case .symlink: "This is a link to an app, not the app itself"
            case .doesNotExist: "The app no longer exists"
            case .notOwnedByYou: "Installed for all users (needs an administrator)"
            case .folderNotWritable: "You can't change the folder this app is in"
            case .appleApp: "Part of macOS"
            case .appStoreApp: "From the App Store. Remove it from Launchpad or Finder."
            case .running: "Open right now. Quit it first."
            case .protectedApp: "Mac Cleaner can't remove itself"
            case .sipProtected: "Protected by System Integrity Protection"
            case .identityChanged: "The app changed since it was scanned"
            }
        }
    }

    private let folders: [[String]]
    public var protectedBundleIDs: Set<String>

    public init(applicationFolders: [URL], protectedBundleIDs: Set<String> = ["io.github.maccleaner.app"]) {
        folders = applicationFolders
            .compactMap { SafetyGuard.realpath($0.path(percentEncoded: false)) }
            .map(SafetyGuard.components)
        self.protectedBundleIDs = protectedBundleIDs
    }

    public func validate(_ url: URL, running: [String]) throws(Rejection) -> SafetyGuard.ValidatedPath {
        guard url.isFileURL, url.pathExtension == "app" else { throw .notAnApp }
        let lexical = SafetyGuard.lexicallyNormalized(url.path(percentEncoded: false))
        guard let name = lexical.last else { throw .notAnApp }
        guard let parent = SafetyGuard.realpath("/" + lexical.dropLast().joined(separator: "/")) else { throw .doesNotExist }
        let parentComponents = SafetyGuard.components(parent)
        let inFolder = folders.contains { $0 == parentComponents || (parentComponents.count == $0.count + 1 && Array(parentComponents.prefix($0.count)) == $0) }
        guard inFolder else { throw .notInApplicationsFolder }

        let path = SafetyGuard.join(parentComponents + [name])
        var st = stat()
        guard lstat(path, &st) == 0 else { throw .doesNotExist }
        guard (st.st_mode & S_IFMT) != S_IFLNK else { throw .symlink }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { throw .notAnApp }
        guard st.st_flags & UInt32(SF_RESTRICTED) == 0 else { throw .sipProtected }
        guard st.st_uid == getuid() else { throw .notOwnedByYou }
        guard access(parent, W_OK) == 0 else { throw .folderNotWritable }

        let appURL = URL(fileURLWithPath: path, isDirectory: true)
        if let id = Bundle(url: appURL)?.bundleIdentifier, protectedBundleIDs.contains(id) { throw .protectedApp }
        let signature = SignatureChecker.status(of: appURL)
        if signature == .apple { throw .appleApp }
        if Self.isAppStoreApp(appURL, signature: signature) { throw .appStoreApp }
        if running.contains(where: { $0.hasPrefix(path + "/") }) { throw .running }

        return SafetyGuard.ValidatedPath(url: appURL, device: Int64(st.st_dev), inode: UInt64(st.st_ino), isSymlink: false)
    }

    public func revalidate(_ scanned: SafetyGuard.ValidatedPath, running: [String]) throws(Rejection) -> SafetyGuard.ValidatedPath {
        let fresh = try validate(scanned.url, running: running)
        guard fresh.device == scanned.device, fresh.inode == scanned.inode else { throw .identityChanged }
        return fresh
    }

    static func isAppStoreApp(_ url: URL, signature: SignatureStatus) -> Bool {
        if case .appStore = signature { return true }
        return FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt").path(percentEncoded: false))
    }
}
