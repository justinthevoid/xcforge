import Foundation
import Testing

@testable import XCForgeKit

@Suite("Physical devices and Device Hub", .serialized)
struct DeviceSupportTests {

  // MARK: - Device Hub

  @Test("Device Hub is preferred over Simulator.app when the selected Xcode has it")
  func simulatorAppPaths() {
    let dev = "/Applications/Xcode.app/Contents/Developer"
    let hub = "/Applications/Xcode.app/Contents/Applications/DeviceHub.app"
    let sim = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
    #expect(SimulatorApp.installedPath(developerDir: dev, exists: { $0 == hub || $0 == sim }) == hub)
    #expect(SimulatorApp.installedPath(developerDir: dev, exists: { $0 == sim }) == sim)
    #expect(SimulatorApp.installedPath(developerDir: dev, exists: { _ in false }) == nil)
    #expect(SimulatorApp.isSimulatorApp(bundleID: "com.apple.dt.Devices"))
    #expect(SimulatorApp.isSimulatorApp(bundleID: "com.apple.iphonesimulator"))
    #expect(!SimulatorApp.isSimulatorApp(bundleID: "com.apple.dt.Xcode"))
  }

  // MARK: - devicectl JSON

  @Test("device fields are read from Xcode 27 `properties` and the older split layout")
  func devicectlLayouts() {
    let legacy: [String: Any] = [
      "identifier": "CORE-1",
      "deviceProperties": ["name": "Justin's iPhone", "developerModeStatus": "enabled"],
      "hardwareProperties": ["udid": "00008110-AAA"],
      "connectionProperties": ["tunnelIPAddress": "fd00::1", "pairingState": "paired"],
    ]
    // Xcode 27.2 nests `properties` by group.
    let modern: [String: Any] = [
      "identifier": "CORE-2",
      "properties": [
        "hardware": ["reality": "physical", "udid": "00008120-BBB"],
        "state": ["name": "Test iPad", "bootState": "booted"],
        "connection": ["state": "connected", "transportType": "localNetwork", "tunnelIPAddress": "fd00::2"],
      ],
    ]
    let list: [String: Any] = ["result": ["devices": [legacy, modern]]]

    let byName = DeviceWDA.findDevice("Justin's iPhone", listJSON: list)
    #expect(byName?.udid == "00008110-AAA")
    #expect(byName?.tunnelIP == "fd00::1")
    #expect(byName?.developerMode == "enabled")
    let byUDID = DeviceWDA.findDevice("00008120-BBB", listJSON: list)
    #expect(byUDID?.name == "Test iPad")
    #expect(DeviceWDA.findDevice("CORE-1", listJSON: list)?.udid == "00008110-AAA")
    #expect(DeviceWDA.findDevice("nope", listJSON: list) == nil)
  }

  @Test("Xcode 27 simulators in devicectl output are dropped, and state comes from the tunnel")
  func devicectlSimulatorsAndState() {
    let phone: [String: Any] = [
      "identifier": "CORE-1",
      "visibilityClass": "default",
      "hardwareProperties": ["udid": "00008110-AAA", "reality": "physical", "platform": "iOS"],
      "deviceProperties": ["name": "Phone", "osVersionNumber": "27.0"],
      "connectionProperties": ["tunnelState": "disconnected", "pairingState": "paired", "transportType": "wired"],
    ]
    let virtual: [String: Any] = [
      "identifier": "SIM-1",
      "properties": ["name": "iPhone 17", "udid": "SIM-1", "reality": "virtual", "bootState": "booted"],
    ]
    let simPlatform: [String: Any] = [
      "identifier": "SIM-2",
      "properties": ["name": "iPad Air", "udid": "SIM-2", "platform": "iOS Simulator"],
    ]
    let unlabeled: [String: Any] = ["identifier": "SIM-3", "properties": ["name": "iPhone Air", "udid": "sim-3"]]
    // Shapes captured from Xcode 27.2's devicectl (values masked).
    let wifiPhone: [String: Any] = [
      "identifier": "CORE-9",
      "visibilityClass": "default",
      "connectionProperties": ["pairingState": "paired", "transportType": "localNetwork", "tunnelState": "connected"],
      "deviceProperties": ["bootState": "booted", "name": "Owner's iPhone", "osVersionNumber": "27.2"],
      "hardwareProperties": ["platform": "iOS", "reality": "physical", "udid": "00008150-CCC"],
      "properties": [
        "connection": ["state": "connected", "transportType": "localNetwork"],
        "hardware": ["reality": "physical", "udid": "00008150-CCC"],
        "state": ["bootState": "booted", "name": "Owner's iPhone"],
      ],
    ]
    let hubSimulator: [String: Any] = [
      "identifier": "CORE-10",
      "visibilityClass": "simulators",
      "connectionProperties": ["transportType": "sameMachine", "tunnelState": "connected"],
      "deviceProperties": ["name": "iPhone 17", "provider": "com.apple.CoreSimulator.SimulatorCoreDevicePlugin"],
      "hardwareProperties": ["platform": "iOS", "reality": "simulated", "udid": "SIM-UDID"],
      "properties": ["hardware": ["reality": "simulated", "udid": "SIM-UDID"], "state": ["name": "iPhone 17"]],
    ]
    let wifi = DeviceTools.physicalEntry(wifiPhone)
    #expect(wifi?.udid == "00008150-CCC")
    #expect(wifi?.name == "Owner's iPhone")
    #expect(wifi?.state == "connected")
    #expect(wifi?.connectionType == "localNetwork")
    #expect(DeviceTools.physicalEntry(hubSimulator) == nil)

    let entry = DeviceTools.physicalEntry(phone)
    #expect(entry?.state == "disconnected")
    #expect(entry?.connectionType == "wired")
    #expect(DeviceTools.physicalEntry(virtual) == nil)
    #expect(DeviceTools.physicalEntry(simPlatform) == nil)
    #expect(DeviceTools.physicalEntry(unlabeled, simulatorUDIDs: ["SIM-3"]) == nil)
    #expect(DeviceTools.physicalEntry(unlabeled)?.state == "unknown")

    let list: [String: Any] = ["result": ["devices": [virtual, phone]]]
    #expect(DeviceWDA.findDevice("iPhone 17", listJSON: list) == nil)
    #expect(DeviceWDA.findDevice("Phone", listJSON: list)?.udid == "00008110-AAA")
  }

  // MARK: - WDA URL discovery

  @Test("the URL WDA logs is extracted, and the tunnel address is tried first")
  func wdaURLs() {
    let log = "noise\nServerURLHere->http://192.168.1.20:8100<-ServerURLHere\nmore"
    #expect(DeviceWDA.loggedServerURL(log) == "http://192.168.1.20:8100")
    #expect(DeviceWDA.loggedServerURL("nothing") == nil)
    #expect(
      DeviceWDA.candidateURLs(tunnelIP: "fd00::1", loggedURL: "http://192.168.1.20:8100/", port: 8100)
        == ["http://[fd00::1]:8100", "http://192.168.1.20:8100"])
    #expect(DeviceWDA.candidateURLs(tunnelIP: "10.0.0.2", loggedURL: nil, port: 9000) == ["http://10.0.0.2:9000"])
  }

  @Test("known device failures become one actionable sentence")
  func failureExplanations() {
    #expect(DeviceWDA.explainFailure("Enable UI Automation in Settings")?.contains("UI Automation") == true)
    #expect(DeviceWDA.explainFailure("The device is passcode protected")?.contains("locked") == true)
    #expect(DeviceWDA.explainFailure("Developer Mode disabled")?.contains("Developer Mode") == true)
    #expect(
      DeviceWDA.explainFailure("Signing for \"WebDriverAgentRunner\" requires a development team")?
        .contains("--team") == true)
    #expect(DeviceWDA.explainFailure("Build succeeded") == nil)
  }

  @Test("runner bundle id is team-specific by default")
  func runnerBundleID() {
    #expect(DeviceWDA.runnerBundleID(team: "ABCDE12345", explicit: nil) == "com.xcforge.wda.abcde12345.runner")
    #expect(DeviceWDA.runnerBundleID(team: nil, explicit: nil) == "com.xcforge.wda.runner")
    #expect(DeviceWDA.runnerBundleID(team: "X", explicit: "com.me.wda") == "com.me.wda")
  }

  // MARK: - State and base URL

  @Test("a saved device runner is found by name or UDID and selects the WDA URL")
  func savedStateSelectsURL() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-wda-\(UUID().uuidString)").path
    setenv("XCFORGE_WDA_STATE_DIR", dir, 1)
    defer {
      unsetenv("XCFORGE_WDA_STATE_DIR")
      try? FileManager.default.removeItem(atPath: dir)
    }
    let state = DeviceWDA.State(
      udid: "00008110-AAA", name: "Phone", url: "http://[fd00::1]:8100", pid: 1, logPath: "/tmp/x.log",
      bundleID: "com.xcforge.wda.runner.xctrunner", startedAt: Date())
    DeviceWDA.save(state)

    #expect(DeviceWDA.load(device: "00008110-AAA")?.url == state.url)
    #expect(DeviceWDA.load(device: "Phone")?.udid == "00008110-AAA")
    #expect(WDAClient.defaultBaseURL(environment: ["XCFORGE_DEVICE": "Phone"]) == state.url)
    #expect(
      WDAClient.defaultBaseURL(environment: ["XCFORGE_DEVICE": "Phone", "WDA_BASE_URL": "http://h:1"])
        == "http://h:1")
    #expect(WDAClient.defaultBaseURL(environment: [:]) == "http://localhost:8100")
  }

  @Test("a device WDA URL is remote; localhost is not")
  func remoteDetection() async {
    let client = WDAClient()
    await client.setBaseURL("http://[fd00::1]:8100")
    #expect(await client.isRemote)
    await client.setBaseURL("http://localhost:8100")
    #expect(!(await client.isRemote))
  }
}
