import Darwin
import Foundation

public struct SizeInfo: Sendable, Hashable {
    /// Sum of file lengths (what Finder calls "size"); sparse holes included.
    public var logicalBytes: Int64 = 0
    /// Sum of `totalFileAllocatedSize`; each hard-linked inode counted once.
    public var allocatedBytes: Int64 = 0
    /// Space that removing this item would actually free. Excludes blocks
    /// shared with APFS clones and hard-linked files that have links outside
    /// the item. Never larger than `allocatedBytes`.
    public var reclaimableBytes: Int64 = 0
    public var fileCount: Int = 0
    /// Newest modification date of the item or anything inside it.
    public var newestModification: Date?
    /// False if some entries could not be read.
    public var isComplete: Bool = true
}

/// Read-only size measurement. Never follows symlinks.
public enum SizeCalculator {

    public static func measure(_ url: URL) -> SizeInfo? {
        let rootPath = url.path(percentEncoded: false)
        var rootStat = stat()
        guard lstat(rootPath, &rootStat) == 0 else { return nil }

        var acc = Accumulator()
        acc.add(path: rootPath, url: url, stat: rootStat)

        if (rootStat.st_mode & S_IFMT) == S_IFDIR {
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
            var hadError = false
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in hadError = true; return true }
            )
            while let child = enumerator?.nextObject() as? URL {
                if Task.isCancelled { hadError = true; break }
                let path = child.path(percentEncoded: false)
                var st = stat()
                guard lstat(path, &st) == 0 else { hadError = true; continue }
                acc.add(path: path, url: child, stat: st)
            }
            if hadError { acc.info.isComplete = false }
        }
        return acc.finish()
    }

    /// Bytes of the file that are not shared with an APFS clone, or nil when
    /// the volume does not report it.
    static func privateSize(_ path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &list, raw.baseAddress, raw.count, UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED))
        }
        guard status == 0 else { return nil }
        // Layout: u_int32_t length; attribute_set_t returned (5 × u_int32_t:
        // common, vol, dir, file, fork); off_t private size.
        return buffer.withUnsafeBytes { raw -> Int64? in
            let returnedFork = raw.loadUnaligned(fromByteOffset: 4 + 16, as: UInt32.self)
            guard returnedFork & UInt32(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return raw.loadUnaligned(fromByteOffset: 24, as: Int64.self)
        }
    }

    private struct InodeKey: Hashable {
        let device: Int32
        let inode: UInt64
    }

    private struct HardLink {
        var seen: Int
        let linkCount: Int
        let reclaimable: Int64
    }

    private struct Accumulator {
        var info = SizeInfo()
        var seenInodes = Set<InodeKey>()
        var hardLinks: [InodeKey: HardLink] = [:]

        mutating func add(path: String, url: URL, stat st: stat) {
            let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
            if info.newestModification.map({ mtime > $0 }) ?? true {
                info.newestModification = mtime
            }

            let type = st.st_mode & S_IFMT
            guard type == S_IFREG else {
                // Directories and symlinks: count the entry, not its target.
                if type != S_IFDIR { info.fileCount += 1 }
                return
            }
            info.fileCount += 1

            let key = InodeKey(device: st.st_dev, inode: UInt64(st.st_ino))
            let firstSighting = seenInodes.insert(key).inserted

            if firstSighting {
                let allocated = Int64(
                    (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize)
                        ?? Int(st.st_blocks) * 512
                )
                let reclaimable = min(allocated, SizeCalculator.privateSize(path) ?? allocated)
                info.logicalBytes += Int64(st.st_size)
                info.allocatedBytes += allocated

                if st.st_nlink > 1 {
                    hardLinks[key] = HardLink(seen: 1, linkCount: Int(st.st_nlink), reclaimable: reclaimable)
                } else {
                    info.reclaimableBytes += reclaimable
                }
            } else {
                hardLinks[key]?.seen += 1
            }
        }

        mutating func finish() -> SizeInfo {
            // A hard-linked file only frees space if every link is inside.
            for link in hardLinks.values where link.seen >= link.linkCount {
                info.reclaimableBytes += link.reclaimable
            }
            return info
        }
    }
}
