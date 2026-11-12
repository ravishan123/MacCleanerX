import Darwin
import Foundation

/// Paths currently open (or used as working directory) by the current user's
/// processes, captured once per scan/clean with libproc.
///
/// Limitations: processes of other users are not visible, and files that are
/// only memory-mapped without an open descriptor are not detected.
public struct OpenFileSnapshot: Sendable {
    /// Canonical paths, sorted for prefix lookups.
    private let sortedPaths: [String]

    public init(paths: some Sequence<String>) {
        sortedPaths = Set(paths).sorted()
    }

    public static let empty = OpenFileSnapshot(paths: [])

    /// True if `url` itself, or anything inside it, is open.
    public func isInUse(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let prefix = trimmed + "/"
        // First element >= trimmed.
        var low = 0, high = sortedPaths.count
        while low < high {
            let mid = (low + high) / 2
            if sortedPaths[mid] < trimmed { low = mid + 1 } else { high = mid }
        }
        var i = low
        while i < sortedPaths.count {
            let candidate = sortedPaths[i]
            if candidate == trimmed || candidate.hasPrefix(prefix) { return true }
            // Sorted order: once past the "trimmed/" range there is no match,
            // but names like "trimmed-x" sort between, so keep scanning while
            // the candidate still starts with `trimmed`.
            guard candidate.hasPrefix(trimmed) else { break }
            i += 1
        }
        return false
    }

    public static func capture() -> OpenFileSnapshot {
        var paths: [String] = []
        for pid in userProcessIDs() {
            if let cwd = workingDirectory(of: pid) { paths.append(cwd) }
            paths.append(contentsOf: openVnodePaths(of: pid))
        }
        return OpenFileSnapshot(paths: paths)
    }

    /// PIDs of the current user's processes.
    static func userProcessIDs() -> [pid_t] {
        let uid = UInt32(getuid())
        let needed = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.stride + 64)
        let bytes = pids.withUnsafeMutableBytes { raw in
            proc_listpids(UInt32(PROC_UID_ONLY), uid, raw.baseAddress, Int32(raw.count))
        }
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
    }

    private static func openVnodePaths(of pid: pid_t) -> [String] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let bytes = fds.withUnsafeMutableBytes { raw in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, raw.baseAddress, Int32(raw.count))
        }
        guard bytes > 0 else { return [] }

        var result: [String] = []
        for fd in fds.prefix(Int(bytes) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { continue }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { cString(from: $0) }
            if !path.isEmpty { result.append(path) }
        }
        return result
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { cString(from: $0) }
        return path.isEmpty ? nil : path
    }

    private static func cString(from raw: UnsafeRawBufferPointer) -> String {
        let bytes = raw.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
