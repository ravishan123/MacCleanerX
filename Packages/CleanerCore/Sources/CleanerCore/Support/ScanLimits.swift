import Foundation

/// Runs blocking file-system work with a bounded number of tasks at once.
///
/// Scans do synchronous I/O. Starting every module at the same time fills the
/// whole cooperative thread pool and starves everything else, so only a few
/// run together. Cancelling the calling task cancels the running ones and
/// stops new ones from starting.
public enum ScanLimits {
    public static let maxConcurrent = 4

    public static func run<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        limit: Int = maxConcurrent,
        isolation: isolated (any Actor)? = #isolation,
        work: @escaping @Sendable (Input) async -> Output,
        onResult: (Output) -> Void
    ) async {
        await withTaskGroup(of: Output.self, isolation: isolation) { group in
            var next = 0
            func startNext() {
                guard next < inputs.count, !Task.isCancelled else { return }
                let input = inputs[next]
                next += 1
                group.addTask { await work(input) }
            }
            for _ in 0..<max(1, limit) { startNext() }
            while let output = await group.next() {
                onResult(output)
                startNext()
            }
        }
    }
}
