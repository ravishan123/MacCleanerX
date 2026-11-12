import Darwin
import Foundation

/// Detects whether the app has Full Disk Access by trying to open files that
/// macOS only lets FDA-approved apps read. Opening a file for reading changes
/// nothing.
public enum FullDiskAccess {
    public enum Status: Sendable, Hashable {
        case granted, denied, unknown
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    public static let loginItemsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
    public static let storageSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!

    static let probes = [
        "Library/Application Support/com.apple.TCC/TCC.db",
        "Library/Safari/Bookmarks.plist",
        "Library/Safari/CloudTabs.db",
    ]

    public static func status(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Status {
        var sawDenied = false
        for probe in probes {
            let path = home.appending(path: probe).path(percentEncoded: false)
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return .granted
            }
            if errno == EPERM || errno == EACCES { sawDenied = true }
        }
        return sawDenied ? .denied : .unknown
    }
}
