import Foundation
import Testing

@testable import XCForgeKit

/// URLProtocol-based stub WDA. Registered globally; intercepts every HTTP request
/// `URLSession.shared` issues for the duration of a test. Responses are queued per
/// `"METHOD path"` key so tests can script ordered behavior (e.g. session-dead-then-success).
final class StubWDAProtocol: URLProtocol, @unchecked Sendable {
  struct Response {
    let status: Int
    let body: [String: Any]
  }

  static let lock = NSLock()
  // nonisolated(unsafe) is required because URLProtocol cannot adopt Sendable;
  // all access goes through `lock`.
  nonisolated(unsafe) static var responses: [String: [Response]] = [:]
  nonisolated(unsafe) static var log: [(method: String, path: String)] = []

  static func enqueue(_ method: String, _ path: String, status: Int = 200, body: [String: Any] = [:]) {
    lock.lock()
    defer { lock.unlock() }
    let key = "\(method) \(path)"
    responses[key, default: []].append(Response(status: status, body: body))
  }

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    responses = [:]
    log = []
  }

  static func snapshotLog() -> [(method: String, path: String)] {
    lock.lock()
    defer { lock.unlock() }
    return log
  }

  override class func canInit(with request: URLRequest) -> Bool {
    // Limit interception to WDA's default loopback so an accidentally-leaked registration
    // (e.g. a parallel suite running concurrently) cannot intercept unrelated network calls.
    guard let host = request.url?.host else { return false }
    return host == "localhost" || host == "127.0.0.1"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let method = request.httpMethod ?? "GET"
    let path = request.url?.path ?? ""

    Self.lock.lock()
    Self.log.append((method, path))
    let key = "\(method) \(path)"
    let next = Self.responses[key]?.first
    if next != nil {
      Self.responses[key]?.removeFirst()
    }
    Self.lock.unlock()

    guard let resp = next, let url = request.url else {
      let err = NSError(
        domain: "StubWDA", code: 0,
        userInfo: [NSLocalizedDescriptionKey: "No stub queued for \(key)"])
      client?.urlProtocol(self, didFailWithError: err)
      return
    }

    let data = (try? JSONSerialization.data(withJSONObject: resp.body)) ?? Data()
    let httpResp = HTTPURLResponse(
      url: url,
      statusCode: resp.status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: httpResp, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

/// Run `body` with `StubWDAProtocol` registered globally; reset state on entry/exit.
private func withStubbedWDA<T>(_ body: () async throws -> T) async rethrows -> T {
  StubWDAProtocol.reset()
  URLProtocol.registerClass(StubWDAProtocol.self)
  defer {
    URLProtocol.unregisterClass(StubWDAProtocol.self)
    StubWDAProtocol.reset()
  }
  return try await body()
}

@Suite("WDA session auto-bootstrap retry", .serialized)
struct WDASessionRetryTests {

  // MARK: - Happy path: healthy session → no retry

  // Tests use `tap(x:y:)` because it is wrapped in withSessionRetry; element-bound calls
  // (click, getText, etc.) are intentionally not wrapped — see AgentClient.swift comment.

  @Test("Action succeeds on first try; no retry path entered")
  func healthyPath() async throws {
    try await withStubbedWDA {
      // ensureSession() (sessionId nil) → ensureWDARunning → GET /status → 200
      StubWDAProtocol.enqueue("GET", "/status", body: ["value": ["ready": true]])
      // → createSession → POST /session → s1
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      // → tap → POST /session/s1/actions → 200
      StubWDAProtocol.enqueue("POST", "/session/s1/actions", body: ["value": ""])

      let client = WDAClient()
      try await client.tap(x: 100, y: 200)

      let log = StubWDAProtocol.snapshotLog()
      #expect(log.count == 3, "expected 3 requests, got \(log.count): \(log)")
      #expect(log.last?.path == "/session/s1/actions")
    }
  }

  // MARK: - Session-dead 404 → retry once → success

  @Test("Session-dead 404 invalidates session, recreates, retries once and succeeds")
  func sessionDeadRetrySucceeds() async throws {
    try await withStubbedWDA {
      StubWDAProtocol.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      // First tap → 404 with "no such session" → triggers retry
      StubWDAProtocol.enqueue(
        "POST", "/session/s1/actions",
        status: 404,
        body: ["value": ["message": "no such session: s1 is gone"]]
      )
      // Retry path: createSession (no ensureWDARunning, since WDA returned an HTTP response)
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s2"])
      // Retried tap → 200
      StubWDAProtocol.enqueue("POST", "/session/s2/actions", body: ["value": ""])

      let client = WDAClient()
      try await client.tap(x: 100, y: 200)  // must succeed via retry

      let log = StubWDAProtocol.snapshotLog()
      // Expect: status, /session, /session/s1/actions, /session, /session/s2/actions
      #expect(log.count == 5, "expected 5 requests, got \(log.count): \(log)")
      #expect(log[2].path == "/session/s1/actions")
      #expect(log[3].method == "POST" && log[3].path == "/session")
      #expect(log[4].path == "/session/s2/actions")
    }
  }

  // MARK: - Non-session 4xx must not retry

  @Test("Non-session 400 propagates without retry")
  func nonSessionErrorDoesNotRetry() async throws {
    await withStubbedWDA {
      StubWDAProtocol.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      // 400 with a non-session message → not a session-dead signature
      StubWDAProtocol.enqueue(
        "POST", "/session/s1/actions",
        status: 400,
        body: ["value": ["message": "invalid argument: coordinates out of bounds"]]
      )

      let client = WDAClient()
      var caught: Error?
      do {
        try await client.tap(x: 100, y: 200)
      } catch {
        caught = error
      }

      #expect(caught != nil, "expected tap() to throw")
      let log = StubWDAProtocol.snapshotLog()
      #expect(log.count == 3, "must not retry; got \(log.count) requests: \(log)")
    }
  }

  // MARK: - Session dead, retry's recreate also fails

  @Test("Session-dead followed by failing recreate surfaces the recreate error")
  func sessionDeadRetryFailsOnRecreate() async throws {
    await withStubbedWDA {
      StubWDAProtocol.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      StubWDAProtocol.enqueue(
        "POST", "/session/s1/actions",
        status: 404,
        body: ["value": ["message": "no such session: s1 is gone"]]
      )
      // Retry's createSession fails with 500
      StubWDAProtocol.enqueue(
        "POST", "/session",
        status: 500,
        body: ["value": ["message": "session create blew up"]]
      )

      let client = WDAClient()
      var caught: Error?
      do {
        try await client.tap(x: 100, y: 200)
      } catch {
        caught = error
      }

      #expect(caught != nil, "expected throw after recreate failure")
      // Confirm the recreate attempt surfaced its 500, not the original 404
      if case let WDAError.wdaError(status, _)? = caught as? WDAError {
        #expect(status == 500, "expected recreate's 500 to surface, got status \(status)")
      } else {
        Issue.record("expected WDAError.wdaError, got \(String(describing: caught))")
      }
      // Confirm the second /session POST was attempted exactly once (no further retries)
      let log = StubWDAProtocol.snapshotLog()
      let sessionCreates = log.filter { $0.method == "POST" && $0.path == "/session" }
      #expect(
        sessionCreates.count == 2,
        "expected exactly two POST /session, got \(sessionCreates.count)")
    }
  }

  // MARK: - Element-bound calls are NOT auto-retried

  @Test("Element-bound click on session-dead surfaces session error without retry")
  func elementBoundDoesNotRetry() async throws {
    await withStubbedWDA {
      StubWDAProtocol.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      StubWDAProtocol.enqueue(
        "POST", "/session/s1/element/e1/click",
        status: 404,
        body: ["value": ["message": "no such session: s1 is gone"]]
      )

      let client = WDAClient()
      var caught: Error?
      do {
        try await client.click(elementId: "e1")
      } catch {
        caught = error
      }

      #expect(caught != nil, "expected click() to throw the original session-dead error")
      let log = StubWDAProtocol.snapshotLog()
      let sessionCreates = log.filter { $0.method == "POST" && $0.path == "/session" }
      #expect(
        sessionCreates.count == 1,
        "element-bound calls must not auto-recreate session; got \(sessionCreates.count)")
    }
  }

  // MARK: - isSessionDead matcher

  @Test("isSessionDead matches WebDriver session-not-found signatures only")
  func sessionDeadMatcher() async throws {
    let client = WDAClient()
    // Match: 404 + "no such session"
    let m1 = await client.isSessionDead(WDAError.wdaError(404, "no such session: abc"))
    #expect(m1 == true)
    // Match: 404 + "invalid session id"
    let m2 = await client.isSessionDead(WDAError.wdaError(404, "Invalid session id received"))
    #expect(m2 == true)
    // No match: 400 with session text
    let m3 = await client.isSessionDead(WDAError.wdaError(400, "no such session"))
    #expect(m3 == false)
    // No match: 404 unrelated
    let m4 = await client.isSessionDead(WDAError.wdaError(404, "element not found"))
    #expect(m4 == false)
    // No match: connectivity error
    let m5 = await client.isSessionDead(WDAError.wdaNotResponding)
    #expect(m5 == false)
  }

  // MARK: - bundleId persistence across recreates (G1 + G4 root fix)
  //
  // The original bug: `ensureSession()` recreated sessions without a bundleId, so any
  // auto-bootstrapped WDA session was unbound — queries defaulted to whatever app WDA
  // picked and could not see app-owned secondary windows (sheets, alerts, fullScreenCover).
  // These tests live in this suite (not a sibling) so they share the `.serialized` trait
  // and `withStubbedWDA` harness — cross-suite parallelism stomps the global URLProtocol.

  @Test("createSession(bundleId:) records activeBundleId for future recreates")
  func recordsActiveBundleId() async throws {
    try await withStubbedWDA {
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])

      let client = WDAClient()
      #expect(await client.getActiveBundleId() == nil)

      _ = try await client.createSession(bundleId: "com.example.foo")

      #expect(await client.getActiveBundleId() == "com.example.foo")
    }
  }

  @Test("createSession() with no arg reuses persisted activeBundleId")
  func nilArgReusesPersisted() async throws {
    try await withStubbedWDA {
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s2"])

      let client = WDAClient()
      _ = try await client.createSession(bundleId: "com.example.foo")
      _ = try await client.createSession()

      #expect(await client.getActiveBundleId() == "com.example.foo")
    }
  }

  @Test("clearActiveBundleId resets the persisted state to nil")
  func clearResetsBundleId() async throws {
    try await withStubbedWDA {
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])

      let client = WDAClient()
      _ = try await client.createSession(bundleId: "com.example.foo")
      await client.clearActiveBundleId()
      #expect(await client.getActiveBundleId() == nil)
    }
  }

  @Test("verifyActiveBundleId reads CFBundleIdentifier from /session GET response")
  func verifyReadsCFBundleIdentifier() async throws {
    try await withStubbedWDA {
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      StubWDAProtocol.enqueue(
        "GET", "/session/s1",
        body: [
          "value": [
            "capabilities": [
              "CFBundleIdentifier": "com.example.foo"
            ]
          ]
        ])

      let client = WDAClient()
      _ = try await client.createSession(bundleId: "com.example.foo")
      let bound = try await client.verifyActiveBundleId()
      #expect(bound == "com.example.foo")
    }
  }

  @Test("verifyActiveBundleId returns nil when WDA reports no CFBundleIdentifier")
  func verifyReturnsNilWhenUnset() async throws {
    try await withStubbedWDA {
      StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
      StubWDAProtocol.enqueue(
        "GET", "/session/s1",
        body: [
          "value": [
            "capabilities": [:] as [String: Any]
          ]
        ])

      let client = WDAClient()
      _ = try await client.createSession(bundleId: "com.example.foo")
      let bound = try await client.verifyActiveBundleId()
      #expect(bound == nil)
    }
  }
}
