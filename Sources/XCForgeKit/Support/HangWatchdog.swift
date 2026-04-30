import Foundation

/// Samples a running xcodebuild process at fixed intervals while it is active.
///
/// Spawn one watchdog per xcodebuild invocation; call `cancel()` when the process finishes.
/// Cancelling before the first deadline fires leaves zero side effects — no snapshot files written.
final class HangWatchdog: Sendable {
  private let task: Task<DiagnosticSnapshot.Result?, Never>

  init(udid: String?, snapshotPath: String, sampleAt: [TimeInterval], env: Environment) {
    task = Task {
      var last: DiagnosticSnapshot.Result?
      let start = Date()
      for deadline in sampleAt {
        let remaining = deadline - Date().timeIntervalSince(start)
        if remaining > 0 {
          do {
            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
          } catch {
            return last
          }
        }
        guard !Task.isCancelled else { return last }
        last = await DiagnosticSnapshot.capture(udid: udid, snapshotPath: snapshotPath, env: env)
      }
      return last
    }
  }

  /// Cancel the watchdog. Safe to call from any concurrency context. Returns immediately.
  func cancel() {
    task.cancel()
  }

  /// The most recent diagnostic result, or nil if no sample fired before cancellation.
  /// Awaiting after `cancel()` returns quickly once any in-flight capture finishes.
  var latestResult: DiagnosticSnapshot.Result? {
    get async { await task.value }
  }
}
