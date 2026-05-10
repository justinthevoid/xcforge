import Foundation
import Testing

@testable import XCForgeKit

/// Private URLProtocol stub (one per test file) so we don't race the global
/// `StubWDAProtocol` registered/unregistered concurrently by other suites.
private final class StubWDABundleHint: URLProtocol, @unchecked Sendable {
  struct Response {
    let status: Int
    let body: [String: Any]
  }

  static let lock = NSLock()
  nonisolated(unsafe) static var responses: [String: [Response]] = [:]
  nonisolated(unsafe) static var log: [(method: String, path: String)] = []
  nonisolated(unsafe) static var bodies: [String: [[String: Any]]] = [:]

  static func enqueue(
    _ method: String, _ path: String, status: Int = 200, body: [String: Any] = [:]
  ) {
    lock.lock()
    defer { lock.unlock() }
    responses["\(method) \(path)", default: []].append(Response(status: status, body: body))
  }

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    responses = [:]
    log = []
    bodies = [:]
  }

  static func snapshotLog() -> [(method: String, path: String)] {
    lock.lock()
    defer { lock.unlock() }
    return log
  }

  static func lastRequestBody(method: String, path: String) -> [String: Any]? {
    lock.lock()
    defer { lock.unlock() }
    return bodies["\(method) \(path)"]?.last
  }

  /// Unique port so we don't compete with other suites' URLProtocol subclasses for
  /// the default WDA base URL. Other suites' stubs intercept :8100; we only intercept :18101.
  static let stubPort = 18101

  override class func canInit(with request: URLRequest) -> Bool {
    guard let host = request.url?.host, let port = request.url?.port else { return false }
    return (host == "localhost" || host == "127.0.0.1") && port == Self.stubPort
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let method = request.httpMethod ?? "GET"
    let path = request.url?.path ?? ""

    let bodyJSON: [String: Any]? = {
      if let raw = request.httpBody,
        let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
      {
        return obj
      }
      if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let read = stream.read(&buf, maxLength: 4096)
          if read <= 0 { break }
          data.append(buf, count: read)
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      }
      return nil
    }()

    Self.lock.lock()
    Self.log.append((method, path))
    let key = "\(method) \(path)"
    let next = Self.responses[key]?.first
    if next != nil { Self.responses[key]?.removeFirst() }
    if let body = bodyJSON { Self.bodies[key, default: []].append(body) }
    Self.lock.unlock()

    guard let resp = next, let url = request.url else {
      let err = NSError(
        domain: "StubWDABundleHint", code: 0,
        userInfo: [NSLocalizedDescriptionKey: "No stub queued for \(key)"])
      client?.urlProtocol(self, didFailWithError: err)
      return
    }

    let data = (try? JSONSerialization.data(withJSONObject: resp.body)) ?? Data()
    let httpResp = HTTPURLResponse(
      url: url, statusCode: resp.status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: httpResp, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func withStubbedBundleHintWDA<T>(_ body: () async throws -> T) async rethrows -> T {
  StubWDABundleHint.reset()
  URLProtocol.registerClass(StubWDABundleHint.self)
  defer {
    URLProtocol.unregisterClass(StubWDABundleHint.self)
    StubWDABundleHint.reset()
  }
  return try await body()
}

/// Tests for the launched-bundle hint + active-bundle poll added so `pose` no longer
/// has to rely on a fixed pre-screenshot sleep, and `ui ls --source wda` after a
/// `pose` no longer silently activates Springboard.
@Suite("WDA bundle hint + active-bundle poll", .serialized)
struct WDABundleHintTests {

  /// After `recordLaunchedApp`, the next implicit `ensureSession()` must POST a
  /// session with the recorded bundleId in `capabilities.alwaysMatch.bundleId` —
  /// otherwise WDA defaults to Springboard and silently backgrounds the user's app
  /// on the first `ui ls`.
  @Test("recordLaunchedApp seeds bundleId into the next createSession capability")
  func recordedBundleIdReachesCreateSession() async throws {
    try await withStubbedBundleHintWDA {
      StubWDABundleHint.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDABundleHint.enqueue("POST", "/session", body: ["sessionId": "s-bound"])

      let client = WDAClient()
      await client.setBaseURL("http://localhost:\(StubWDABundleHint.stubPort)")
      await client.recordLaunchedApp(bundleId: "com.example.app")
      _ = try await client.ensureSession()

      let body = StubWDABundleHint.lastRequestBody(method: "POST", path: "/session")
      let caps = (body?["capabilities"] as? [String: Any])?["alwaysMatch"] as? [String: Any]
      #expect(caps?["bundleId"] as? String == "com.example.app")
    }
  }

  @Test("pollForActiveBundleId returns true on first match")
  func pollMatchesImmediately() async throws {
    try await withStubbedBundleHintWDA {
      StubWDABundleHint.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDABundleHint.enqueue("POST", "/session", body: ["sessionId": "s-poll"])
      StubWDABundleHint.enqueue(
        "GET", "/session/s-poll",
        body: ["value": ["capabilities": ["CFBundleIdentifier": "com.example.app"]]])

      let client = WDAClient()
      await client.setBaseURL("http://localhost:\(StubWDABundleHint.stubPort)")
      _ = try await client.ensureSession()

      let matched = await client.pollForActiveBundleId(
        target: "com.example.app", budget: 1.0)
      #expect(matched == true)
    }
  }

  @Test("pollForActiveBundleId returns false on empty target without network calls")
  func pollEmptyTargetShortCircuits() async {
    await withStubbedBundleHintWDA {
      let client = WDAClient()
      await client.setBaseURL("http://localhost:\(StubWDABundleHint.stubPort)")
      let matched = await client.pollForActiveBundleId(target: "  ", budget: 5.0)
      #expect(matched == false)
      #expect(StubWDABundleHint.snapshotLog().isEmpty)
    }
  }

  /// When `recordLaunchedApp` switches to a *different* bundle while a session
  /// already exists, the cached `sessionId` (bound to the old bundle) must be
  /// invalidated — otherwise `ensureSession()`'s quick health check happily reuses
  /// it and queries hit the wrong app. Verified by observing a fresh `POST /session`
  /// after the switch.
  @Test("recordLaunchedApp invalidates session when bundleId changes")
  func bundleSwitchInvalidatesSession() async throws {
    try await withStubbedBundleHintWDA {
      // First ensureSession: status + session for app A
      StubWDABundleHint.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDABundleHint.enqueue("POST", "/session", body: ["sessionId": "s-A"])
      // After bundle switch, ensureSession must re-create — status + new session.
      StubWDABundleHint.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDABundleHint.enqueue("POST", "/session", body: ["sessionId": "s-B"])

      let client = WDAClient()
      await client.setBaseURL("http://localhost:\(StubWDABundleHint.stubPort)")
      await client.recordLaunchedApp(bundleId: "com.example.A")
      _ = try await client.ensureSession()

      // Switch bundles — must drop the cached sessionId.
      await client.recordLaunchedApp(bundleId: "com.example.B")
      _ = try await client.ensureSession()

      // Two POST /session calls = sessionId was invalidated.
      let log = StubWDABundleHint.snapshotLog()
      let posts = log.filter { $0.method == "POST" && $0.path == "/session" }
      #expect(posts.count == 2)
    }
  }

  @Test("pollForActiveBundleId returns false on zero budget without network calls")
  func pollZeroBudgetShortCircuits() async {
    await withStubbedBundleHintWDA {
      let client = WDAClient()
      await client.setBaseURL("http://localhost:\(StubWDABundleHint.stubPort)")
      let matched = await client.pollForActiveBundleId(
        target: "com.example.app", budget: 0)
      #expect(matched == false)
      #expect(StubWDABundleHint.snapshotLog().isEmpty)
    }
  }
}
