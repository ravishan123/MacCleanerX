import Foundation

/// The only two primitives that change the file system. Injected so tests can
/// substitute a fake Trash inside their fixture folder.
public struct FileOperations: Sendable {
    /// Moves the item to the user's Trash and returns its new location.
    public var moveToTrash: @Sendable (URL) throws -> URL?
    /// Removes the item immediately. Never follows symlinks.
    public var deletePermanently: @Sendable (URL) throws -> Void

    public init(
        moveToTrash: @escaping @Sendable (URL) throws -> URL?,
        deletePermanently: @escaping @Sendable (URL) throws -> Void
    ) {
        self.moveToTrash = moveToTrash
        self.deletePermanently = deletePermanently
    }

    /// Real operations. `trashItem` behaves like `NSWorkspace.recycle` (items
    /// can be put back from the Trash) without pulling AppKit into the core.
    public static let live = FileOperations(
        moveToTrash: { url in
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        },
        deletePermanently: { url in
            try FileManager.default.removeItem(at: url)
        }
    )
}
