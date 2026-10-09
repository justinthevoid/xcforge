import Foundation

/// Serializes every test that registers a URLProtocol stub for WDA's localhost URL.
///
/// Each WDA suite is `.serialized` internally, but suites run in parallel and all their
/// stubs answer `localhost`, so one suite's stub (or its `reset()`) could swallow another
/// suite's requests. Holding this gate for the whole stubbed region keeps them apart.
actor WDAStubGate {
  static let shared = WDAStubGate()

  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    if !busy {
      busy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty {
      busy = false
    } else {
      waiters.removeFirst().resume()
    }
  }

  /// Release from a synchronous `defer`.
  nonisolated func releaseSoon() {
    Task { await release() }
  }
}
