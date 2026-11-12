import Foundation

/// Xcode build products and device support files, plus simulators whose
/// runtime is no longer installed.
///
/// - DerivedData, DeviceSupport, simulator caches: Safe (rebuilt on demand).
/// - Archives: Review (needed to symbolicate or re-export shipped builds).
/// - Unavailable simulators: removed with `xcrun simctl delete unavailable`.
///   That cannot go to the Trash, so it requires permanent-deletion mode.
public struct XcodeJunkModule: CleanupModule {
    public let category = CleanupCategory.xcodeJunk

    public enum Group {
        public static let derivedData = "DerivedData"
        public static let archives = "Archives"
        public static let deviceSupport = "Device support"
        public static let simulatorCaches = "Simulator caches"
        public static let simulators = "Simulators"
    }

    static let deviceSupportFolders = [
        "iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport",
    ]

    private let context: ModuleContext
    private let support: PathModuleSupport

    public init(context: ModuleContext) {
        self.context = context
        support = PathModuleSupport(category: category, context: context, roots: Self.roots(for: context))
    }

    private static func xcode(_ context: ModuleContext) -> URL {
        context.developer.appending(path: "Xcode", directoryHint: .isDirectory)
    }

    static func roots(for context: ModuleContext) -> [URL] {
        let xcode = xcode(context)
        return [
            xcode.appending(path: "DerivedData", directoryHint: .isDirectory),
            xcode.appending(path: "Archives", directoryHint: .isDirectory),
            context.developer.appending(path: "CoreSimulator/Caches", directoryHint: .isDirectory),
        ] + deviceSupportFolders.map { xcode.appending(path: $0, directoryHint: .isDirectory) }
    }

    public func scan() async -> [Finding] {
        let roots = Self.roots(for: context)
        var sources: [ScanSource] = [
            .topLevel(roots[0], risk: .safe, accessGroup: Group.derivedData, group: { _ in Group.derivedData }),
            // Archives/<date>/<name>.xcarchive → one finding per archive.
            ScanSource(root: roots[1], risk: .review, accessGroup: Group.archives) { root in
                try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    .flatMap { day in
                        ((try? FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)) ?? [])
                            .filter { $0.pathExtension == "xcarchive" }
                    }
                    .map { (url: $0, group: Group.archives) }
            },
            .topLevel(roots[2], risk: .safe, accessGroup: Group.simulatorCaches, group: { _ in Group.simulatorCaches }),
        ]
        sources += roots.dropFirst(3).map {
            .topLevel($0, risk: .safe, accessGroup: Group.deviceSupport, group: { _ in Group.deviceSupport })
        }

        var findings = await support.scan(sources)
        if let simulators = await unavailableSimulatorsFinding() {
            findings.append(simulators)
        }
        return findings
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        let commands = findings.filter { $0.target == .command(.deleteUnavailableSimulators) && $0.category == category }
        let files = findings.filter { $0.target != .command(.deleteUnavailableSimulators) }
        var result = support.clean(files, mode: mode)

        for finding in commands {
            switch mode {
            case .dryRun:
                result.removed.append(.init(findingID: finding.id, target: finding.target, bytes: finding.reclaimableBytes, trashedURL: nil))
            case .moveToTrash:
                result.failed.append(.init(
                    findingID: finding.id, target: finding.target,
                    reason: "Simulators can't be moved to the Trash. Choose “Delete permanently” to remove them."
                ))
            case .deletePermanently:
                do {
                    let output = try await context.commandRunner.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
                    if output.status == 0 {
                        result.removed.append(.init(findingID: finding.id, target: finding.target, bytes: finding.reclaimableBytes, trashedURL: nil))
                    } else {
                        result.failed.append(.init(findingID: finding.id, target: finding.target,
                                                   reason: "simctl failed: \(output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))"))
                    }
                } catch {
                    result.failed.append(.init(findingID: finding.id, target: finding.target, reason: "\(error)"))
                }
            }
        }
        return result
    }

    /// Read-only: `xcrun simctl list devices unavailable -j`.
    func unavailableSimulatorsFinding() async -> Finding? {
        guard let output = try? await context.commandRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"]),
              output.status == 0
        else { return nil }
        let devices = Self.parseUnavailableDevices(output.stdout)
        guard !devices.isEmpty else { return nil }

        let bytes = devices.reduce(Int64(0)) { total, device in
            guard let dataPath = device.dataPath else { return total }
            let deviceFolder = URL(fileURLWithPath: dataPath).deletingLastPathComponent()
            return total + (SizeCalculator.measure(deviceFolder)?.reclaimableBytes ?? 0)
        }
        return Finding(
            category: category,
            target: .command(.deleteUnavailableSimulators),
            group: Group.simulators,
            reclaimableBytes: bytes,
            risk: .safe
        )
    }

    struct SimulatorDevice: Decodable {
        let udid: String
        let name: String
        let dataPath: String?
    }

    static func parseUnavailableDevices(_ json: Data) -> [SimulatorDevice] {
        struct Listing: Decodable { let devices: [String: [SimulatorDevice]] }
        return (try? JSONDecoder().decode(Listing.self, from: json))?.devices.values.flatMap { $0 } ?? []
    }
}
