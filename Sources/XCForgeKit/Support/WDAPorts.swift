import Foundation

/// One WebDriverAgent port per simulator, so two booted simulators each get their own
/// runner: taps go to the simulator the screenshot came from, and one session's cleanup
/// never kills another's runner. Assignments are saved so the CLI and the MCP server agree.
enum WDAPorts {
  static let basePort = 8100
  static let maxPorts = 100

  static func path() -> String {
    if let override = ProcessInfo.processInfo.environment["XCFORGE_WDA_PORTS_FILE"], !override.isEmpty {
      return override
    }
    return NSHomeDirectory() + "/.xcforge/wda/simulator-ports.json"
  }

  /// The port for `udid`, assigning the lowest free one on first use.
  static func port(for udid: String, path: String = path()) -> Int {
    var ports = load(path)
    if let existing = ports[udid] { return existing }
    let port = assign(udid, in: ports)
    ports[udid] = port
    save(ports, path)
    return port
  }

  /// The lowest port from `basePort` no other simulator holds.
  static func assign(_ udid: String, in ports: [String: Int]) -> Int {
    let taken = Set(ports.filter { $0.key != udid }.values)
    return (basePort..<(basePort + maxPorts)).first { !taken.contains($0) } ?? basePort
  }

  private static func load(_ path: String) -> [String: Int] {
    guard let data = FileManager.default.contents(atPath: path),
      let ports = try? JSONDecoder().decode([String: Int].self, from: data)
    else { return [:] }
    return ports
  }

  private static func save(_ ports: [String: Int], _ path: String) {
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(ports) {
      try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
  }
}
