import Foundation
import Testing

@testable import XCForgeKit

/// Mock shell that returns canned values for `simctl getenv SIMULATOR_MAINSCREEN_*`.
private actor SimEnvShell: ShellExecutor {
  private(set) var calls: [[String]] = []
  let widthRaw: String
  let heightRaw: String
  let scaleRaw: String

  init(widthRaw: String, heightRaw: String, scaleRaw: String) {
    self.widthRaw = widthRaw
    self.heightRaw = heightRaw
    self.scaleRaw = scaleRaw
  }

  func record(_ args: [String]) { calls.append(args) }
  func recorded() -> [[String]] { calls }

  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    await record(arguments)
    return await dispatch(arguments)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    await record(arguments)
    return await dispatch(arguments)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  private func dispatch(_ args: [String]) -> ShellResult {
    guard args.count >= 4, args[0] == "simctl", args[1] == "getenv" else {
      return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }
    switch args[3] {
    case "SIMULATOR_MAINSCREEN_WIDTH":
      return ShellResult(stdout: widthRaw, stderr: "", exitCode: 0)
    case "SIMULATOR_MAINSCREEN_HEIGHT":
      return ShellResult(stdout: heightRaw, stderr: "", exitCode: 0)
    case "SIMULATOR_MAINSCREEN_SCALE":
      return ShellResult(stdout: scaleRaw, stderr: "", exitCode: 0)
    default:
      return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }
  }
}

private actor MissingEnvShell: ShellExecutor {
  let missingKey: String

  init(missingKey: String = "SIMULATOR_MAINSCREEN_SCALE") { self.missingKey = missingKey }

  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    await dispatch(arguments)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    await dispatch(arguments)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  private func dispatch(_ args: [String]) -> ShellResult {
    guard args.count >= 4, args[0] == "simctl", args[1] == "getenv" else {
      return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }
    if args[3] == missingKey {
      return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }
    switch args[3] {
    case "SIMULATOR_MAINSCREEN_WIDTH": return ShellResult(stdout: "750", stderr: "", exitCode: 0)
    case "SIMULATOR_MAINSCREEN_HEIGHT": return ShellResult(stdout: "1334", stderr: "", exitCode: 0)
    case "SIMULATOR_MAINSCREEN_SCALE": return ShellResult(stdout: "2.000000", stderr: "", exitCode: 0)
    default: return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }
  }
}

@Suite("sim info")
struct SimInfoTests {
  @Test("fetchScreenInfo derives point size from pixel/scale (iPhone 8: 750×1334 @2x)")
  func fetchScreenInfoIPhone8() async throws {
    let shell = SimEnvShell(widthRaw: "750", heightRaw: "1334", scaleRaw: "2.000000")
    let env = Environment(shell: shell)

    let info = try await SimTools.fetchScreenInfo(
      udid: "AAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", env: env)

    #expect(info.scale == 2.0)
    #expect(info.pixelSize.width == 750)
    #expect(info.pixelSize.height == 1334)
    #expect(info.pointSize.width == 375)
    #expect(info.pointSize.height == 667)

    let calls = await shell.recorded()
    let envCalls = calls.filter { $0.contains("getenv") }
    #expect(envCalls.count == 3, "expected 3 getenv calls (W/H/SCALE), got: \(envCalls)")
  }

  @Test("fetchScreenInfo throws when scale is missing")
  func fetchScreenInfoMissingScaleErrors() async throws {
    let shell = MissingEnvShell(missingKey: "SIMULATOR_MAINSCREEN_SCALE")
    let env = Environment(shell: shell)

    await #expect(throws: SimTools.ScreenInfoError.self) {
      _ = try await SimTools.fetchScreenInfo(udid: "FAKE-UDID", env: env)
    }
  }
}
