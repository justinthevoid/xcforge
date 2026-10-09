import CoreGraphics
import Foundation
import MCP
import Testing

@testable import XCForgeKit

/// Records simctl calls and answers `content_size` reads with a fixed value.
private actor RecordingShell: ShellExecutor {
  private(set) var calls: [[String]] = []
  let contentSize: String

  init(contentSize: String = "large") {
    self.contentSize = contentSize
  }

  func record(_ args: [String]) -> ShellResult {
    calls.append(args)
    if args.count == 4, args[1] == "ui", args[3] == "content_size" {
      return ShellResult(stdout: contentSize + "\n", stderr: "", exitCode: 0)
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    await record(arguments)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    await record(arguments)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

@Suite("UI driving: the right screen, small trees, waits, screenshots, sim setup")
struct UIDrivingTests {
  static let udid = "11111111-2222-3333-4444-555555555555"

  // MARK: - One WDA per simulator

  @Test("each simulator gets its own WDA port, kept across processes")
  func wdaPorts() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xcf-ports-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let path = (dir as NSString).appendingPathComponent("ports.json")
    #expect(WDAPorts.port(for: "A", path: path) == 8100)
    #expect(WDAPorts.port(for: "B", path: path) == 8101)
    #expect(WDAPorts.port(for: "A", path: path) == 8100)
    #expect(WDAPorts.assign("C", in: ["A": 8100, "B": 8102]) == 8101)
  }

  @Test("a recreated session never relaunches the app; the alert action is passed on")
  func sessionCapabilities() {
    let recreated = WDAClient.sessionCapabilities(bundleId: "com.example.app", recreating: true, alertAction: nil)
    #expect(recreated["forceAppLaunch"] as? Bool == false)
    let first = WDAClient.sessionCapabilities(bundleId: "com.example.app", recreating: false, alertAction: "accept")
    #expect(first["forceAppLaunch"] == nil)
    #expect(first["defaultAlertAction"] as? String == "accept")
    #expect(WDAClient.sessionCapabilities(bundleId: nil, recreating: true, alertAction: nil).isEmpty)
  }

  @Test("UI tools gain simulator; actions gain wait_for, until_gone and timeout")
  func augmentedSchemas() throws {
    let tap = try #require(UITools.tools.first { $0.name == "click_element" })
    let augmented = UIWait.augment(UITarget.augment(tap))
    guard case .object(let schema) = augmented.inputSchema else {
      Issue.record("schema is not an object")
      return
    }
    let properties = schema["properties"]?.objectValue ?? [:]
    for key in ["simulator", "wait_for", "until_gone", "timeout"] {
      #expect(properties[key] != nil, "missing \(key)")
    }
    let build = Tool(name: "build_sim", description: "", inputSchema: .object(["type": .string("object")]))
    #expect(UIWait.augment(UITarget.augment(build)).inputSchema == build.inputSchema)
  }

  @Test("waits match an element by id or label, quotes escaped")
  func waitPredicate() {
    #expect(UIWait.predicate(for: "Save") == "name == 'Save' OR label == 'Save'")
    #expect(UIWait.predicate(for: "Don't") == "name == 'Don\\'t' OR label == 'Don\\'t'")
  }

  // MARK: - Trees

  @Test("the tree drops wrappers, hidden and off-screen nodes, and keeps value/enabled/selected")
  func flattenedTree() {
    let source: [String: Any] = [
      "type": "XCUIElementTypeApplication", "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
      "children": [
        [
          "type": "XCUIElementTypeOther", "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
          "children": [
            [
              "type": "XCUIElementTypeTextField", "name": "email", "value": "a@b.c", "isEnabled": "1",
              "rect": ["x": 20, "y": 100, "width": 350, "height": 44],
            ],
            [
              "type": "XCUIElementTypeButton", "label": "Save", "isEnabled": "0", "isSelected": "1",
              "rect": ["x": 20, "y": 700, "width": 100, "height": 44],
            ],
            ["type": "XCUIElementTypeButton", "rect": ["x": 300, "y": 40, "width": 44, "height": 44]],
            [
              "type": "XCUIElementTypeButton", "label": "Hidden", "isVisible": "0",
              "rect": ["x": 20, "y": 760, "width": 100, "height": 44],
            ],
            [
              "type": "XCUIElementTypeButton", "label": "Far", "rect": ["x": 500, "y": 100, "width": 50, "height": 44],
            ],
            ["type": "XCUIElementTypeStaticText", "label": "Zero", "rect": ["x": 0, "y": 0, "width": 0, "height": 0]],
          ],
        ]
      ],
    ]
    let elements = UITools.flattenWDASource(source)
    // The unlabeled button stays: it can still be tapped.
    #expect(elements.map(\.label) == ["", "Save", "", "Zero"])
    #expect(elements[2].type == "XCUIElementTypeButton")
    #expect(elements[0].identifier == "email")
    #expect(elements[0].value == "a@b.c")
    #expect(elements[1].enabled == false)
    #expect(elements[1].selected == true)
  }

  // MARK: - Coordinate taps

  @Test("taps in a rotated interface are turned back to the portrait digitizer")
  func orientationNormalization() {
    func ratio(_ x: Double, _ y: Double, _ o: IndigoHIDClient.Orientation) -> [Float] {
      let r = IndigoHIDClient.normalize(x: x, y: y, portraitWidth: 400, portraitHeight: 800, orientation: o)
      return [r.0, r.1]
    }
    #expect(ratio(100, 200, .portrait) == [0.25, 0.25])
    #expect(ratio(100, 200, .portraitUpsideDown) == [0.75, 0.75])
    // Landscape interfaces are 800 wide and 400 tall.
    #expect(ratio(200, 100, .landscapeLeft) == [0.75, 0.25])
    #expect(ratio(200, 100, .landscapeRight) == [0.25, 0.75])
    #expect(ratio(-5, 9000, .portrait) == [0, 1])

    #expect(IndigoHIDClient.Orientation(wdaValue: "PORTRAIT") == .portrait)
    #expect(IndigoHIDClient.Orientation(wdaValue: "LANDSCAPE") == .landscapeLeft)
    #expect(IndigoHIDClient.Orientation(wdaValue: "UIA_DEVICE_ORIENTATION_LANDSCAPERIGHT") == .landscapeRight)
    #expect(IndigoHIDClient.Orientation(wdaValue: "UIA_DEVICE_ORIENTATION_PORTRAIT_UPSIDEDOWN") == .portraitUpsideDown)
  }

  // MARK: - Screenshots

  @Test("crops are x,y,width,height in points and clip to the image")
  func cropParsing() throws {
    let crop = try #require(ScreenshotShaping.parseCrop("0, 100, 390, 200"))
    #expect(crop == ScreenshotShaping.PointRect(x: 0, y: 100, width: 390, height: 200))
    #expect(ScreenshotShaping.parseCrop("0,100,390") == nil)
    #expect(ScreenshotShaping.parseCrop("0,100,0,200") == nil)
    #expect(ScreenshotShaping.parseCrop("a,b,c,d") == nil)

    let rect = ScreenshotShaping.pixelRect(crop, scale: 3, imageWidth: 1170, imageHeight: 2532)
    #expect(rect == CGRect(x: 0, y: 300, width: 1170, height: 600))
    let past = ScreenshotShaping.PointRect(x: 300, y: 0, width: 200, height: 10)
    #expect(ScreenshotShaping.pixelRect(past, scale: 3, imageWidth: 1170, imageHeight: 2532)?.width == 270)
    let outside = ScreenshotShaping.PointRect(x: 500, y: 0, width: 10, height: 10)
    #expect(ScreenshotShaping.pixelRect(outside, scale: 3, imageWidth: 1170, imageHeight: 2532) == nil)
  }

  @Test("max_dimension bounds the longer side and keeps the aspect ratio")
  func scaledSize() {
    let shrunk = ScreenshotShaping.scaledSize(width: 1170, height: 2532, maxDimension: 800)
    #expect(shrunk.width == 370)
    #expect(shrunk.height == 800)
    let small = ScreenshotShaping.scaledSize(width: 300, height: 200, maxDimension: 800)
    #expect(small.width == 300)
    #expect(small.height == 200)
    #expect(ScreenshotShaping.pointsPerPixel(outputWidth: 370, croppedPointWidth: 390) > 1)
  }

  @Test("each capture gets its own file")
  func uniquePaths() {
    let a = ScreenshotShaping.uniquePath(format: "png")
    let b = ScreenshotShaping.uniquePath(format: "png")
    #expect(a != b)
    #expect(a.hasSuffix(".png"))
  }

  @Test("crop and max_dimension are in the screenshot schema")
  func screenshotSchema() throws {
    let tool = try #require(ScreenshotTools.tools.first { $0.name == "screenshot" })
    guard case .object(let schema) = tool.inputSchema else {
      Issue.record("schema is not an object")
      return
    }
    let properties = schema["properties"]?.objectValue ?? [:]
    #expect(properties["crop"] != nil)
    #expect(properties["max_dimension"] != nil)
  }

  // MARK: - Simulator setup

  @Test("setting the text size reports the size it replaced")
  func contentSize() async {
    let shell = RecordingShell(contentSize: "extra-large")
    let env = Environment(shell: shell)
    let result = await SimTools.executeContentSize(simulator: Self.udid, size: "accessibility-large", env: env)
    #expect(result.succeeded)
    #expect(result.message.contains("was extra-large"))
    let calls = await shell.calls
    #expect(calls.last == ["simctl", "ui", Self.udid, "content_size", "accessibility-large"])

    let unknown = await SimTools.executeContentSize(simulator: Self.udid, size: "huge", env: env)
    #expect(!unknown.succeeded)
  }

  @Test("a locale implies its language; Portuguese and Chinese keep the region")
  func localeLanguage() {
    #expect(SimTools.language(forLocale: "fr_FR") == "fr")
    #expect(SimTools.language(forLocale: "pt_BR") == "pt-BR")
    #expect(SimTools.language(forLocale: "zh-Hant_TW") == "zh-Hant")
    #expect(SimTools.language(forLocale: "ar") == "ar")
  }

  @Test("setting the locale writes AppleLocale and AppleLanguages")
  func locale() async {
    let shell = RecordingShell()
    let env = Environment(shell: shell)
    let result = await SimTools.executeLocale(simulator: Self.udid, locale: "de_DE", language: nil, env: env)
    #expect(result.succeeded)
    let writes = await shell.calls.filter { $0.contains("write") }
    let written = writes.map { Array($0.suffix(3)) }
    #expect(written == [["AppleLocale", "-string", "de_DE"], ["AppleLanguages", "-array", "de"]])
  }

  @Test("push payloads must be JSON objects; plain text becomes the alert")
  func pushPayload() throws {
    let wrapped = try #require(SimTools.pushPayload("Hello"))
    let object = try JSONSerialization.jsonObject(with: wrapped) as? [String: Any]
    #expect((object?["aps"] as? [String: Any])?["alert"] as? String == "Hello")
    #expect(SimTools.pushPayload("{\"aps\":{\"badge\":1}}") != nil)
    #expect(SimTools.pushPayload("{not json") == nil)
  }

  @Test("privacy grants name the app; a reset without one covers every app")
  func privacy() async {
    let shell = RecordingShell()
    let env = Environment(shell: shell)
    let grant = await SimTools.executePrivacy(
      simulator: Self.udid, action: "grant", service: "photos", bundleId: "com.example.app", env: env)
    #expect(grant.succeeded)
    let reset = await SimTools.executePrivacy(
      simulator: Self.udid, action: "reset", service: "all", bundleId: nil, env: env)
    #expect(reset.succeeded)
    let calls = await shell.calls
    #expect(calls.contains(["simctl", "privacy", Self.udid, "grant", "photos", "com.example.app"]))
    #expect(calls.contains(["simctl", "privacy", Self.udid, "reset", "all"]))

    let bad = await SimTools.executePrivacy(
      simulator: Self.udid, action: "allow", service: "photos", bundleId: "com.example.app", env: env)
    #expect(!bad.succeeded)
  }
}
