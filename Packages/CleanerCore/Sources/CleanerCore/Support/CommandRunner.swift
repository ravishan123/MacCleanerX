import Foundation

public struct CommandOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data = Data()) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum CommandError: Error, Sendable, CustomStringConvertible {
    case unavailable
    case notAllowed(String)

    public var description: String {
        switch self {
        case .unavailable: "Command running is not available"
        case .notAllowed(let tool): "\(tool) is not an allowed tool"
        }
    }
}

/// Runs external tools. The live runner only executes a fixed set of Apple
/// developer/security tools; tests inject a fake.
public struct CommandRunner: Sendable {
    public var run: @Sendable (_ executable: String, _ arguments: [String]) async throws -> CommandOutput

    public init(run: @escaping @Sendable (_ executable: String, _ arguments: [String]) async throws -> CommandOutput) {
        self.run = run
    }

    /// Safe default: refuses everything.
    public static let unavailable = CommandRunner { _, _ in throw CommandError.unavailable }

    public static let allowedTools: Set<String> = ["/usr/bin/xcrun", "/usr/bin/codesign", "/usr/sbin/spctl"]

    public static let live = CommandRunner { executable, arguments in
        guard allowedTools.contains(executable) else { throw CommandError.notAllowed(executable) }
        return try await runProcess(executable, arguments)
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    static func runProcess(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // A hung tool must not stall a scan.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
                // Drain both pipes concurrently so a full pipe can't deadlock.
                let errBox = Box()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: CommandOutput(status: process.terminationStatus, stdout: outData, stderr: errBox.data))
            }
        }
    }
}
