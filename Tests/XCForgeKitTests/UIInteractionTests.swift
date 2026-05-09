import Foundation
import MCP
import Testing

@testable import XCForgeKit

/// Stub WDA URLProtocol scoped to a unique loopback alias (`127.0.0.2`) so it cannot
/// race with `StubWDAProtocol` when both suites run in parallel under Swift Testing.
final class StubWDAUITap: URLProtocol, @unchecked Sendable {
  static let stubHost = "127.0.0.2"
  static let stubBaseURL = "http://127.0.0.2:8100"

  struct Response {
    let status: Int
    let body: [String: Any]
  }

  static let lock = NSLock()
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
    request.url?.host == stubHost
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
        domain: "StubWDAUITap", code: 0,
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

/// Construct a WDAClient pre-pointed at the stub host so requests cannot escape to the
/// real loopback (or be intercepted by `StubWDAProtocol`).
private func makeStubbedClient() async -> WDAClient {
  let c = WDAClient()
  await c.setBaseURL(StubWDAUITap.stubBaseURL)
  return c
}

private func withStubbedWDA<T>(_ body: () async throws -> T) async rethrows -> T {
  StubWDAUITap.reset()
  URLProtocol.registerClass(StubWDAUITap.self)
  defer {
    URLProtocol.unregisterClass(StubWDAUITap.self)
    StubWDAUITap.reset()
  }
  return try await body()
}

/// Run `body` with the AXP-skip test hook enabled so `xcforgeRenderUIListing` takes the
/// WDA fallback path (deterministic, stub-driven). On macOS CI the process is often
/// AX-trusted and would otherwise read the real Simulator tree.
///
/// Note: `XCFORGE_SKIP_AXP` is a DEBUG-only hook in `InteractionProvider`. `swift test`
/// builds debug by default, so the env var takes effect; in release builds it is ignored.
private func withAXPSkipped<T>(_ body: () async throws -> T) async rethrows -> T {
  setenv("XCFORGE_SKIP_AXP", "1", 1)
  defer { unsetenv("XCFORGE_SKIP_AXP") }
  return try await body()
}

/// Bootstrap the standard `ensureSession` flow on the stub: GET /status + POST /session.
private func enqueueSessionBootstrap(sid: String = "s1") {
  StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
  StubWDAUITap.enqueue("POST", "/session", body: ["sessionId": sid])
}

@Suite("UI ls + tap-by atomic interaction", .serialized)
struct UIInteractionTests {

  // MARK: - tap-by happy path

  @Test("tap-by-id: success on first click; no retry")
  func tapByIDHappyPath() async throws {
    try await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      // findElement → element id e1
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element",
        body: ["value": ["ELEMENT": "e1"]]
      )
      // click() runs ensureSession first → quick health check on the session.
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      // click → 200
      StubWDAUITap.enqueue("POST", "/session/s1/element/e1/click", body: ["value": ""])

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      let (elementId, retried) = try await xcforgePerformUITap(
        using: "accessibility id", value: "loginButton", env: env
      )

      #expect(elementId == "e1")
      #expect(retried == false)
      let log = StubWDAUITap.snapshotLog()
      let findCount = log.filter { $0.path == "/session/s1/element" }.count
      #expect(findCount == 1, "expected exactly one find on happy path; got log: \(log)")
    }
  }

  // MARK: - tap-by retry on session-dead 404

  @Test("tap-by: session-dead 404 on click triggers re-find + retry, succeeds")
  func tapByRetryOnSessionDead() async throws {
    try await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      // First find → e1
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1"]])
      // click() ensureSession quick-check on s1 → 200
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      // First click → 404 with session-dead message
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element/e1/click",
        status: 404,
        body: ["value": ["message": "no such session: s1 is gone"]]
      )
      // Retry's re-find → withSessionRetry → ensureSession quick-check returns 404 (dead),
      // so withSessionRetry recreates session.
      StubWDAUITap.enqueue(
        "GET", "/session/s1",
        status: 404, body: ["value": ["message": "no such session"]]
      )
      // ensureWDARunning health check before createSession
      StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
      StubWDAUITap.enqueue("POST", "/session", body: ["sessionId": "s2"])
      StubWDAUITap.enqueue(
        "POST", "/session/s2/element", body: ["value": ["ELEMENT": "e2"]])
      // Retry click() ensureSession quick-check on s2 → 200
      StubWDAUITap.enqueue("GET", "/session/s2", body: ["value": ["ready": true]])
      // Retry click → 200
      StubWDAUITap.enqueue("POST", "/session/s2/element/e2/click", body: ["value": ""])

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      let (elementId, retried) = try await xcforgePerformUITap(
        using: "accessibility id", value: "loginButton", env: env
      )

      #expect(retried == true)
      #expect(elementId == "e2")
    }
  }

  // MARK: - tap-by retry on generic 404 stale-element

  @Test("tap-by: generic 404 stale-element on click triggers re-find + retry")
  func tapByRetryOnGenericStale() async throws {
    try await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1"]])
      // click() ensureSession quick-check
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      // 404 with a non-session message (stale element reference / no such element)
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element/e1/click",
        status: 404,
        body: ["value": ["message": "stale element reference"]]
      )
      // Retry: this is NOT session-dead, so withSessionRetry won't recreate session.
      // Re-find on existing session s1, then re-click.
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1b"]])
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      StubWDAUITap.enqueue("POST", "/session/s1/element/e1b/click", body: ["value": ""])

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      let (elementId, retried) = try await xcforgePerformUITap(
        using: "accessibility id", value: "loginButton", env: env
      )

      #expect(retried == true)
      #expect(elementId == "e1b")
    }
  }

  // MARK: - tap-by retry click also fails — second error surfaces

  @Test("tap-by: when retry click also fails, the second error is surfaced")
  func tapBySurfacesSecondError() async throws {
    await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1"]])
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      // First click fails with stale-element 404
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element/e1/click",
        status: 404,
        body: ["value": ["message": "stale element reference"]]
      )
      // Re-find succeeds
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1b"]])
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      // Retry click fails with a distinct error code
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element/e1b/click",
        status: 500,
        body: ["value": ["message": "internal explosion on retry"]]
      )

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      var caught: Error?
      do {
        _ = try await xcforgePerformUITap(
          using: "accessibility id", value: "loginButton", env: env
        )
      } catch {
        caught = error
      }
      #expect(caught != nil, "expected throw")
      if case let WDAError.wdaError(status, msg)? = caught as? WDAError {
        #expect(status == 500, "second error should surface (got \(status))")
        #expect(msg.contains("retry"), "expected the second-attempt message")
      } else {
        Issue.record("expected WDAError.wdaError, got \(String(describing: caught))")
      }
    }
  }

  // MARK: - elementNotFound from findElement does NOT retry

  @Test("tap-by: findElement elementNotFound surfaces immediately without retry")
  func tapByFindElementNotFoundNoRetry() async throws {
    await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      // findElement returns 200 with empty value → triggers WDAError.elementNotFound in client.
      // We need to drive findElement to throw elementNotFound. Per AgentClient.findElement, when
      // the response has no `value.ELEMENT`, it throws elementNotFound.
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element",
        body: ["value": [:] as [String: Any]]
      )

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      var caught: Error?
      do {
        _ = try await xcforgePerformUITap(
          using: "predicate string", value: "label CONTAINS \"Save\"", env: env
        )
      } catch {
        caught = error
      }
      #expect(caught != nil, "expected throw on elementNotFound")
      guard let wdaErr = caught as? WDAError else {
        Issue.record("expected WDAError, got \(type(of: caught as Any))")
        return
      }
      if case .elementNotFound = wdaErr {
        // ok
      } else {
        Issue.record("expected WDAError.elementNotFound, got \(wdaErr)")
      }
      // No retry attempted: only one POST /session/s1/element should have been issued.
      let log = StubWDAUITap.snapshotLog()
      let finds = log.filter { $0.path == "/session/s1/element" }
      #expect(finds.count == 1, "must not retry on elementNotFound; got \(finds.count) finds")
    }
  }

  // MARK: - ls formatting (happy path) using the WDA fallback path

  @Test("ls: formats one-line-per-element with `-` for empty fields")
  func lsFormattingHappyPath() async throws {
    try await withAXPSkipped {
      try await withStubbedWDA {
        // ls path: AXP unavailable in tests → falls through to WDA getSource.
        // getSource performs an isHealthy() check first, then GET /source.
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        let tree: [String: Any] = [
          "type": "Application",
          "name": "root",
          "label": "App",
          "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
          "children": [
            [
              "type": "Button",
              "name": "loginButton",
              "label": "Log In",
              "rect": ["x": 100, "y": 200, "width": 80, "height": 40],
              "children": [],
            ] as [String: Any],
            [
              "type": "StaticText",
              "name": "",
              "label": "Welcome",
              "rect": ["x": 50, "y": 100, "width": 290, "height": 20],
              "children": [],
            ] as [String: Any],
          ],
        ]
        StubWDAUITap.enqueue("GET", "/source", body: tree)

        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        let (body, count, _) = try await xcforgeRenderUIListing(scope: nil, env: env)
        #expect(count >= 2, "expected at least 2 elements; got \(count) — body:\n\(body)")
        #expect(body.contains("loginButton | Log In | Button | 100,200,80,40"))
        // Empty identifier should render as `-`
        #expect(body.contains("- | Welcome | StaticText | 50,100,290,20"))
      }
    }
  }

  // MARK: - ls truncation marker

  @Test("ls: truncates at 50KB and emits trailing summary line")
  func lsTruncation() async throws {
    // Build many synthetic elements so the rendered output crosses 50KB.
    // Each line is ~70 chars; we need 50000/70 ≈ 715+ elements; use 2000 to be safe.
    var children: [[String: Any]] = []
    for i in 0..<2000 {
      children.append(
        [
          "type": "Button",
          "name": "id-\(i)-some-padding-to-grow-the-line-length-aaaaaaaaaaaaaaaaaaaaa",
          "label": "Label \(i) padding xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
          "rect": ["x": i, "y": i, "width": 100, "height": 40],
          "children": [],
        ] as [String: Any])
    }
    let tree: [String: Any] = [
      "type": "Application", "name": "root", "label": "App",
      "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
      "children": children,
    ]

    try await withAXPSkipped {
      try await withStubbedWDA {
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        StubWDAUITap.enqueue("GET", "/source", body: tree)

        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        let (body, count, _) = try await xcforgeRenderUIListing(scope: nil, env: env)
        #expect(count > 100, "expected many elements; got \(count)")
        #expect(body.contains("elements truncated"), "expected truncation marker; body tail: \(body.suffix(200))")
        #expect(body.utf8.count < 60_000, "byte budget exceeded: \(body.utf8.count)")
        let markerOnOwnLine =
          body.contains("\n... ") || body.hasPrefix("... ")
        #expect(markerOnOwnLine, "truncation marker should be on its own line")
      }
    }
  }

  // MARK: - ls scope id missing

  @Test("ls: --scope <id> with missing id surfaces named error")
  func lsScopeMissing() async throws {
    let tree: [String: Any] = [
      "type": "Application", "name": "root", "label": "App",
      "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
      "children": [
        [
          "type": "Button", "name": "alpha", "label": "A",
          "rect": ["x": 0, "y": 0, "width": 10, "height": 10], "children": [],
        ] as [String: Any]
      ],
    ]
    await withAXPSkipped {
      await withStubbedWDA {
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        StubWDAUITap.enqueue("GET", "/source", body: tree)

        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        var caught: Error?
        do {
          _ = try await xcforgeRenderUIListing(scope: "missing-id", env: env)
        } catch {
          caught = error
        }
        #expect(caught != nil, "expected throw")
        let desc = String(describing: caught)
        #expect(desc.contains("missing-id"), "expected scope id named in error: \(desc)")
      }
    }
  }

  // MARK: - Patch 2: generic 404 (non-stale message) is NOT retried

  @Test("tap-by: generic 404 with non-stale message does NOT retry")
  func tapByGeneric404NoRetry() async throws {
    await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1"]])
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      // 404 with body that does NOT match any stale-element signal
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element/e1/click",
        status: 404,
        body: ["value": ["message": "some other 404"]]
      )

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      var caught: Error?
      do {
        _ = try await xcforgePerformUITap(
          using: "accessibility id", value: "loginButton", env: env
        )
      } catch {
        caught = error
      }
      #expect(caught != nil, "expected throw on non-stale 404")
      // Exactly one click attempt; no second find/click.
      let log = StubWDAUITap.snapshotLog()
      let clicks = log.filter { $0.path.contains("/click") }.count
      let finds = log.filter { $0.path == "/session/s1/element" }.count
      #expect(clicks == 1, "must not retry click; got \(clicks) click(s)")
      #expect(finds == 1, "must not re-find on non-stale 404; got \(finds) find(s)")
    }
  }

  // MARK: - Patch 4: applyScope duplicate scope id + zero-frame scope

  @Test("ls: duplicate scope ids — uses first match, includes its descendants")
  func lsDuplicateScope() async throws {
    let tree: [String: Any] = [
      "type": "Application", "name": "root", "label": "App",
      "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
      "children": [
        [
          "type": "Group", "name": "dup", "label": "First",
          "rect": ["x": 0, "y": 0, "width": 200, "height": 200],
          "children": [
            [
              "type": "Button", "name": "child1", "label": "C1",
              "rect": ["x": 10, "y": 10, "width": 50, "height": 30], "children": [],
            ] as [String: Any]
          ],
        ] as [String: Any],
        [
          "type": "Group", "name": "dup", "label": "Second",
          "rect": ["x": 300, "y": 300, "width": 50, "height": 50], "children": [],
        ] as [String: Any],
      ],
    ]
    try await withAXPSkipped {
      try await withStubbedWDA {
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        StubWDAUITap.enqueue("GET", "/source", body: tree)
        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        let (body, count, _) = try await xcforgeRenderUIListing(scope: "dup", env: env)
        // The first 'dup' is at (0,0,200,200) so it contains child1 (10,10,50,30). The
        // second 'dup' at (300,300) is NOT a descendant of the first and must be excluded.
        #expect(count >= 2, "expected first scope + descendant; got \(count)")
        #expect(body.contains("child1"), "expected descendant included: \(body)")
        #expect(!body.contains("Second"), "second duplicate scope must be excluded: \(body)")
      }
    }
  }

  @Test("ls: zero-frame scope returns scope element only (no descendants)")
  func lsZeroFrameScope() async throws {
    let tree: [String: Any] = [
      "type": "Application", "name": "root", "label": "App",
      "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
      "children": [
        [
          "type": "Group", "name": "scopeZero", "label": "Z",
          "rect": ["x": 0, "y": 0, "width": 0, "height": 0], "children": [],
        ] as [String: Any],
        [
          "type": "Button", "name": "other", "label": "O",
          "rect": ["x": 10, "y": 10, "width": 30, "height": 30], "children": [],
        ] as [String: Any],
      ],
    ]
    try await withAXPSkipped {
      try await withStubbedWDA {
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        StubWDAUITap.enqueue("GET", "/source", body: tree)
        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        let (body, count, _) = try await xcforgeRenderUIListing(scope: "scopeZero", env: env)
        #expect(count == 1, "zero-frame scope should yield only itself; got \(count)")
        #expect(body.contains("scopeZero"), "scope element itself should be present")
        #expect(!body.contains("other"), "no descendants when scope frame is zero-area")
      }
    }
  }

  // MARK: - Patch 5: pipe in label is escaped

  @Test("ls: pipe characters in label are escaped to \\|")
  func lsPipeEscaping() async throws {
    let tree: [String: Any] = [
      "type": "Application", "name": "root", "label": "App",
      "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
      "children": [
        [
          "type": "Button", "name": "btn", "label": "Pipe|Inside",
          "rect": ["x": 0, "y": 0, "width": 10, "height": 10], "children": [],
        ] as [String: Any]
      ],
    ]
    try await withAXPSkipped {
      try await withStubbedWDA {
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        StubWDAUITap.enqueue("GET", "/source", body: tree)
        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        let (body, _, _) = try await xcforgeRenderUIListing(scope: nil, env: env)
        #expect(body.contains("Pipe\\|Inside"), "pipe in label must be escaped: \(body)")
      }
    }
  }

  // MARK: - Patch 8: input validation guards

  @Test("tap_by_id: empty id returns fail without invoking WDA")
  func tapByIDEmptyId() async throws {
    let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
    let result = await UITools.dispatch(
      "tap_by_id", ["id": .string("   ")], env: env
    )
    #expect(result != nil)
    #expect(result?.isError == true, "empty id should fail")
  }

  @Test("tap_by: empty using or value returns fail without invoking WDA")
  func tapByEmptyArgs() async throws {
    let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
    let r1 = await UITools.dispatch(
      "tap_by",
      ["using": .string(""), "value": .string("x")],
      env: env
    )
    #expect(r1?.isError == true, "empty using should fail")
    let r2 = await UITools.dispatch(
      "tap_by",
      ["using": .string("accessibility id"), "value": .string("   ")],
      env: env
    )
    #expect(r2?.isError == true, "whitespace-only value should fail")
  }

  @Test("list_elements: whitespace-only scope is treated as missing scope")
  func listElementsWhitespaceScope() async throws {
    try await withAXPSkipped {
      try await withStubbedWDA {
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        let tree: [String: Any] = [
          "type": "Application", "name": "root", "label": "App",
          "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
          "children": [],
        ]
        StubWDAUITap.enqueue("GET", "/source", body: tree)
        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        // Should NOT throw scopeNotFound — whitespace is treated as no scope.
        let (_, _, _) = try await xcforgeRenderUIListing(scope: "   ", env: env)
      }
    }
  }

  // MARK: - Patch 11: MCP dispatch coverage for new tools

  @Test("dispatch tap_by_id surfaces ok with retried token")
  func dispatchTapByID() async throws {
    try await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1"]])
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      StubWDAUITap.enqueue("POST", "/session/s1/element/e1/click", body: ["value": ""])

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      let result = await UITools.dispatch(
        "tap_by_id", ["id": .string("loginButton")], env: env
      )
      #expect(result != nil, "dispatch must route tap_by_id")
      #expect(result?.isError != true, "expected ok")
      // The structured response should embed the parseable retried= token.
      if let content = result?.content.first, case .text(let text, _, _) = content {
        #expect(text.contains("retried=false"), "expected retried=false token in: \(text)")
      } else {
        Issue.record("expected text content in dispatch result")
      }
    }
  }

  @Test("dispatch tap_by surfaces ok with retried token")
  func dispatchTapBy() async throws {
    await withStubbedWDA {
      enqueueSessionBootstrap(sid: "s1")
      StubWDAUITap.enqueue(
        "POST", "/session/s1/element", body: ["value": ["ELEMENT": "e1"]])
      StubWDAUITap.enqueue("GET", "/session/s1", body: ["value": ["ready": true]])
      StubWDAUITap.enqueue("POST", "/session/s1/element/e1/click", body: ["value": ""])

      let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
      let result = await UITools.dispatch(
        "tap_by",
        ["using": .string("accessibility id"), "value": .string("loginButton")],
        env: env
      )
      #expect(result != nil, "dispatch must route tap_by")
      #expect(result?.isError != true, "expected ok")
      if let content = result?.content.first, case .text(let text, _, _) = content {
        #expect(text.contains("retried=false"), "expected retried=false token in: \(text)")
      } else {
        Issue.record("expected text content in dispatch result")
      }
    }
  }

  @Test("dispatch list_elements returns ok via WDA fallback")
  func dispatchListElements() async throws {
    await withAXPSkipped {
      await withStubbedWDA {
        StubWDAUITap.enqueue("GET", "/status", body: ["value": ["ready": true]])
        let tree: [String: Any] = [
          "type": "Application", "name": "root", "label": "App",
          "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
          "children": [
            [
              "type": "Button", "name": "b1", "label": "L1",
              "rect": ["x": 0, "y": 0, "width": 10, "height": 10], "children": [],
            ] as [String: Any]
          ],
        ]
        StubWDAUITap.enqueue("GET", "/source", body: tree)
        let env = await Environment(shell: LiveShell(), wdaClient: makeStubbedClient())
        let result = await UITools.dispatch("list_elements", nil, env: env)
        #expect(result != nil, "dispatch must route list_elements")
        #expect(result?.isError != true, "expected ok")
      }
    }
  }
}
