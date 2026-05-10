import Foundation
import Testing

@testable import XCForgeKit

/// Confirms `WDAClient` source/find paths surface elements that live inside a sibling
/// UIWindow (e.g. SwiftUI .sheet) once WDA has been patched to merge per-window
/// snapshots. The client is payload-shape agnostic — it just forwards whatever WDA
/// returns — so the assertion is that the new payload shape is preserved end-to-end.
///
/// Re-uses the URLProtocol stub harness defined in WDASessionRetryTests.swift; the
/// `.serialized` trait is required because `URLProtocol.registerClass` is global state.
@Suite("WDA multi-window source and find", .serialized)
struct AgentClientMultiWindowTests {

  @Test("getSource returns a payload that contains both the keyWindow and a secondary window subtree")
  func sourceReturnsBothWindows() async throws {
    StubWDAProtocol.reset()
    URLProtocol.registerClass(StubWDAProtocol.self)
    defer {
      URLProtocol.unregisterClass(StubWDAProtocol.self)
      StubWDAProtocol.reset()
    }

    // /source bypasses session creation but does call /status as a fast health check.
    StubWDAProtocol.enqueue("GET", "/status", body: ["value": ["ready": true]])
    // The merged-window XML the patched WDA returns: a synthetic Application root that
    // wraps two Window subtrees, one of which contains the sheet's done button.
    let mergedXML = """
      <?xml version="1.0" encoding="UTF-8"?>
      <XCUIElementTypeApplication name="com.example.host">
        <XCUIElementTypeWindow>
          <XCUIElementTypeButton name="home.primary"/>
        </XCUIElementTypeWindow>
        <XCUIElementTypeWindow>
          <XCUIElementTypeOther name="home.drawer">
            <XCUIElementTypeButton name="home.drawer.done"/>
          </XCUIElementTypeOther>
        </XCUIElementTypeWindow>
      </XCUIElementTypeApplication>
      """
    StubWDAProtocol.enqueue("GET", "/source", body: ["value": mergedXML])

    let client = WDAClient()
    let source = try await client.getSource(format: "xml")

    // The stub returns the body as JSON; getSource decodes the raw response bytes, so
    // the payload arrives JSON-encoded. We just need both window-side identifiers to
    // round-trip — that's the contract the multi-window patch is supposed to preserve.
    #expect(source.contains("home.primary"), "primary window content must round-trip")
    #expect(source.contains("home.drawer.done"), "secondary window sheet element must round-trip")
  }

  @Test("findElement returns a sheet-window element id when WDA's per-window retry resolved it")
  func findElementResolvesSheetMember() async throws {
    StubWDAProtocol.reset()
    URLProtocol.registerClass(StubWDAProtocol.self)
    defer {
      URLProtocol.unregisterClass(StubWDAProtocol.self)
      StubWDAProtocol.reset()
    }

    StubWDAProtocol.enqueue("GET", "/status", body: ["value": ["ready": true]])
    StubWDAProtocol.enqueue("POST", "/session", body: ["sessionId": "s1"])
    // WDA's patched find walks both windows and resolves an id that lives in the sheet.
    StubWDAProtocol.enqueue(
      "POST", "/session/s1/element",
      body: ["value": ["ELEMENT": "elem-from-sheet"]]
    )

    let client = WDAClient()
    let (elementId, _) = try await client.findElement(
      using: "accessibility id", value: "home.drawer.done")

    #expect(elementId == "elem-from-sheet")
    let log = StubWDAProtocol.snapshotLog()
    #expect(log.last?.path == "/session/s1/element")
  }
}
