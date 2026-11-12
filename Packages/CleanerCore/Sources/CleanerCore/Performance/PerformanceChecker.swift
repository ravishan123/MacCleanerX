import Darwin
import Foundation

public enum MemoryPressure: Int, Sendable, Hashable {
    case normal = 1, warning = 2, critical = 4
}

public struct ProcessCPU: Sendable, Hashable {
    public let pid: Int32
    public let name: String
    /// Percent of one CPU core over the sample interval.
    public let percent: Double
}

public struct DiskSpace: Sendable, Hashable {
    public let availableBytes: Int64
    public let totalBytes: Int64
    public var freeFraction: Double { totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 1 }
}

/// Raw measurements. Collected live, or built by hand in tests.
public struct PerformanceSnapshot: Sendable, Hashable {
    public var memoryPressure: MemoryPressure
    public var memoryUsedBytes: Int64
    public var memoryTotalBytes: Int64
    public var topProcesses: [ProcessCPU]
    public var startupItems: [LaunchItem]
    public var disk: DiskSpace?

    public init(memoryPressure: MemoryPressure, memoryUsedBytes: Int64, memoryTotalBytes: Int64,
                topProcesses: [ProcessCPU], startupItems: [LaunchItem], disk: DiskSpace?) {
        self.memoryPressure = memoryPressure
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.topProcesses = topProcesses
        self.startupItems = startupItems
        self.disk = disk
    }
}

public struct PerformanceIssue: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case memoryPressure, cpuHog, startupItems, lowDiskSpace
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
}

public struct PerformanceReport: Sendable, Hashable {
    public let snapshot: PerformanceSnapshot
    public let issues: [PerformanceIssue]
}

/// Thresholds that turn a snapshot into issues. Pure and unit-tested.
public enum PerformanceRules {
    public static let cpuHogPercent = 60.0
    public static let maxReportedHogs = 3
    public static let startupItemsThreshold = 6
    public static let lowDiskFraction = 0.10
    public static let lowDiskBytes: Int64 = 15 * 1_000_000_000

    public static func issues(for s: PerformanceSnapshot) -> [PerformanceIssue] {
        var issues: [PerformanceIssue] = []
        let bytes = ByteCountFormatter()
        bytes.countStyle = .memory

        if s.memoryPressure != .normal {
            issues.append(PerformanceIssue(
                id: "memory",
                kind: .memoryPressure,
                title: s.memoryPressure == .critical ? "Memory is critically low" : "Memory is under pressure",
                detail: "\(bytes.string(fromByteCount: s.memoryUsedBytes)) of \(bytes.string(fromByteCount: s.memoryTotalBytes)) in use. Quitting apps you aren't using frees memory."
            ))
        }

        for process in s.topProcesses.filter({ $0.percent >= cpuHogPercent }).prefix(maxReportedHogs) {
            issues.append(PerformanceIssue(
                id: "cpu-\(process.pid)",
                kind: .cpuHog,
                title: "“\(process.name)” is using a lot of CPU",
                detail: "About \(Int(process.percent.rounded()))% of one core right now."
            ))
        }

        let automatic = s.startupItems.filter { $0.startsAutomatically && !$0.isApple }
        if automatic.count >= startupItemsThreshold {
            issues.append(PerformanceIssue(
                id: "startup",
                kind: .startupItems,
                title: "\(automatic.count) background items start automatically",
                detail: "Each one can slow down startup. Some login items are only listed in System Settings."
            ))
        }

        if let disk = s.disk, disk.freeFraction < lowDiskFraction || disk.availableBytes < lowDiskBytes {
            let files = ByteCountFormatter()
            files.countStyle = .file
            issues.append(PerformanceIssue(
                id: "disk",
                kind: .lowDiskSpace,
                title: "Your startup disk is almost full",
                detail: "\(files.string(fromByteCount: disk.availableBytes)) free of \(files.string(fromByteCount: disk.totalBytes))."
            ))
        }
        return issues
    }
}

/// Collects a live snapshot. Read-only: only sysctl, Mach and libproc queries.
public struct PerformanceChecker: Sendable {
    public var home: URL
    public var sampleInterval: Duration

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, sampleInterval: Duration = .seconds(1)) {
        self.home = home
        self.sampleInterval = sampleInterval
    }

    public func run() async -> PerformanceReport {
        let snapshot = await collect()
        return PerformanceReport(snapshot: snapshot, issues: PerformanceRules.issues(for: snapshot))
    }

    public func collect() async -> PerformanceSnapshot {
        let (used, total) = Self.memoryUsage()
        return PerformanceSnapshot(
            memoryPressure: Self.memoryPressure(),
            memoryUsedBytes: used,
            memoryTotalBytes: total,
            topProcesses: await Self.sampleCPU(interval: sampleInterval),
            startupItems: LaunchItemInventory.items(in: LaunchItemInventory.standardFolders(home: home)),
            disk: Self.diskSpace(at: home)
        )
    }

    static func sysctlInt<T: FixedWidthInteger>(_ name: String, as _: T.Type) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    static func memoryPressure() -> MemoryPressure {
        MemoryPressure(rawValue: Int(sysctlInt("kern.memorystatus_vm_pressure_level", as: Int32.self) ?? 1)) ?? .normal
    }

    static func memoryUsage() -> (used: Int64, total: Int64) {
        let total = Int64(sysctlInt("hw.memsize", as: UInt64.self) ?? 0)
        let pageSize = Int64(sysctlInt("hw.pagesize", as: Int64.self) ?? 16_384)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let pages = Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        return (pages * pageSize, total)
    }

    static func diskSpace(at url: URL) -> DiskSpace? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]),
            let available = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity
        else { return nil }
        return DiskSpace(availableBytes: available, totalBytes: Int64(total))
    }

    /// CPU time of the user's processes, sampled twice.
    static func sampleCPU(interval: Duration) async -> [ProcessCPU] {
        let first = cpuTimes()
        let start = ContinuousClock.now
        try? await Task.sleep(for: interval)
        let elapsed = ContinuousClock.now - start
        let elapsedNs = Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9
        guard elapsedNs > 0 else { return [] }

        let second = cpuTimes()
        let me = getpid()
        return second.compactMap { pid, sample -> ProcessCPU? in
            guard pid != me, let before = first[pid], sample.ns >= before.ns else { return nil }
            return ProcessCPU(pid: pid, name: sample.name, percent: Double(sample.ns - before.ns) / elapsedNs * 100)
        }
        .sorted { $0.percent > $1.percent }
        .prefix(10)
        .map { $0 }
    }

    private static func cpuTimes() -> [Int32: (ns: UInt64, name: String)] {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        var result: [Int32: (UInt64, String)] = [:]
        for pid in OpenFileSnapshot.userProcessIDs() {
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard ok == 0 else { continue }
            let ticks = info.ri_user_time + info.ri_system_time
            let ns = ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            result[pid] = (ns, name.isEmpty ? "Process \(pid)" : name)
        }
        return result
    }
}
