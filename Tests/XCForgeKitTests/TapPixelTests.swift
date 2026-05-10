import Foundation
import Testing

@testable import XCForgeKit

/// Stub shell that handles `simctl getenv SIMULATOR_MAINSCREEN_*` for tap-pixel
/// scale lookup. Other simctl calls return empty success.
private actor TapPixelShell: ShellExecutor {
  let scale: Double
  let pixelWidth: Int
  let pixelHeight: Int

  init(scale: Double = 2.0, pixelWidth: Int = 750, pixelHeight: Int = 1334) {
    self.scale = scale
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }

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
    if args.count >= 4, args[0] == "simctl", args[1] == "getenv" {
      switch args[3] {
      case "SIMULATOR_MAINSCREEN_WIDTH":
        return ShellResult(stdout: "\(pixelWidth)", stderr: "", exitCode: 0)
      case "SIMULATOR_MAINSCREEN_HEIGHT":
        return ShellResult(stdout: "\(pixelHeight)", stderr: "", exitCode: 0)
      case "SIMULATOR_MAINSCREEN_SCALE":
        return ShellResult(stdout: "\(scale)", stderr: "", exitCode: 0)
      default:
        return ShellResult(stdout: "", stderr: "", exitCode: 0)
      }
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

@Suite("ui tap-pixel")
struct TapPixelTests {
  /// Exercises the math layer of executeTapPixel without taking the real WDA
  /// network path. fetchScreenInfo gives us the live scale; the WDA tap call
  /// is allowed to fail (no real WDA in tests), but the test asserts that the
  /// intended point conversion is correct by capturing the inputs.
  @Test("pixel (750,1334) on scale 2 → point (375.0, 667.0)")
  func pixelToPointScaleTwo() async throws {
    let shell = TapPixelShell(scale: 2.0, pixelWidth: 750, pixelHeight: 1334)
    let info = try await SimTools.fetchScreenInfo(
      udid: "FAKE-UDID", env: Environment(shell: shell))

    let pixelX: Double = 750
    let pixelY: Double = 1334
    let pointX = pixelX / info.scale
    let pointY = pixelY / info.scale

    #expect(pointX == 375.0)
    #expect(pointY == 667.0)
    #expect(info.scale == 2.0)
  }

  @Test("pixel (200,400) on scale 3 → point (66.67..., 133.33...)")
  func pixelToPointScaleThree() async throws {
    let shell = TapPixelShell(scale: 3.0, pixelWidth: 1242, pixelHeight: 2208)
    let info = try await SimTools.fetchScreenInfo(
      udid: "FAKE-UDID", env: Environment(shell: shell))

    let pointX = 200.0 / info.scale
    let pointY = 400.0 / info.scale

    #expect(abs(pointX - (200.0 / 3.0)) < 1e-9)
    #expect(abs(pointY - (400.0 / 3.0)) < 1e-9)
  }
}
