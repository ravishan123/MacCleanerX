import CoreServices
import Foundation

/// Turns folder names such as `com.apple.Safari` into an app name for
/// grouping. Uses Launch Services (no UI frameworks). Results are cached.
public enum AppNameResolver {
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String: String] = [:]

        func value(for key: String, compute: () -> String) -> String {
            lock.lock()
            if let cached = names[key] { lock.unlock(); return cached }
            lock.unlock()
            let value = compute()
            lock.lock(); names[key] = value; lock.unlock()
            return value
        }
    }

    /// Display name for a folder named after a bundle identifier, or the
    /// folder name itself when no installed app matches.
    public static func displayName(forFolderName name: String) -> String {
        cache.value(for: name) {
            guard looksLikeBundleID(name) else { return name }
            if let appName = lookUp(bundleID: name) { return appName }
            // Helpers like com.example.App.ShipIt → try the parent identifier.
            var parts = name.split(separator: ".")
            while parts.count > 2 {
                parts.removeLast()
                if let appName = lookUp(bundleID: parts.joined(separator: ".")) { return appName }
            }
            return name
        }
    }

    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && !$0.contains(" ") }
    }

    private static func lookUp(bundleID: String) -> String? {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?
            .takeRetainedValue() as? [URL],
            let url = urls.first
        else { return nil }
        let info = Bundle(url: url)?.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
}
