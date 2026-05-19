import ArgumentParser
import CoreGraphics
import Foundation
import XCForgeKit

struct Screenshot: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "screenshot",
    abstract: "Capture simulator screenshots and manage visual baselines.",
    subcommands: [ScreenshotCapture.self, ScreenshotBaseline.self, ScreenshotCompare.self],
    defaultSubcommand: ScreenshotCapture.self
  )
}

// MARK: - Codable Result Types

struct ScreenshotResult: Codable {
  let succeeded: Bool
  let path: String
  let format: String
  let sizeKB: Int
  /// nil → omitted entirely (JSON shape unchanged for callers passing no new
  /// flags). false only when WDA confirmed the app is NOT foreground; null
  /// when WDA is unreachable (never a false negative).
  let appForeground: Bool?

  init(
    succeeded: Bool, path: String, format: String, sizeKB: Int, appForeground: Bool? = nil
  ) {
    self.succeeded = succeeded
    self.path = path
    self.format = format
    self.sizeKB = sizeKB
    self.appForeground = appForeground
  }

  enum CodingKeys: String, CodingKey {
    case succeeded, path, format, sizeKB, appForeground
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(succeeded, forKey: .succeeded)
    try c.encode(path, forKey: .path)
    try c.encode(format, forKey: .format)
    try c.encode(sizeKB, forKey: .sizeKB)
    try c.encodeIfPresent(appForeground, forKey: .appForeground)
  }
}

struct VisualCompareResult: Codable {
  let passed: Bool
  let diffPercent: Double
  let threshold: Double
  let changedPixels: Int
  let totalPixels: Int
  let baselinePath: String
  let currentPath: String
  let diffPath: String?
}

// MARK: - Capture

struct ScreenshotCapture: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "capture",
    abstract: "Capture a simulator screenshot and save to a file."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Image format: png or jpeg. Default: png")
  var format: String = "png"

  @Option(help: "Output file path. Default: /tmp/xcforge-screenshot.<format>")
  var output: String?

  @Flag(
    help:
      "Overlay a point-coordinate grid (50pt minor lines, 100pt labeled). Failures in the overlay fall back to an ungridded image and warn."
  )
  var grid = false

  @Option(
    name: .customLong("wait-for"),
    help:
      "Readiness signal(s), comma-separated (all must hold): launch-complete, a11y:<id>, text:<substring>. Gates the capture on a real signal (AXP-first, WDA fallback). Warn-only — never fails the screenshot."
  )
  var waitFor: String?

  @Option(
    help:
      "Ceiling in seconds for --wait-for. Capture happens the instant the signal holds. Default 20."
  )
  var timeout: Double?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let output = self.output ?? "/tmp/xcforge-screenshot.\(format)"

    let env = Environment.live
    let sim = try await env.session.resolveSimulator(simulator)

    // Optional readiness gate — warn-only, NEVER hard-fails the screenshot.
    if let waitFor, !waitFor.trimmingCharacters(in: .whitespaces).isEmpty {
      let parsed = ReadinessProbe.Signal.parseSpec(waitFor)
      let probe = await ReadinessProbe.waitReady(
        signals: parsed.signals,
        timeout: timeout ?? 20,
        specWasUnparseable: parsed.allUnparseable,
        simulator: simulator,
        env: env
      )
      if !probe.ready {
        let why = probe.reason ?? "signal(s) not satisfied before timeout"
        fputs(
          "warning: readiness gate not satisfied (mode: \(probe.mode), "
            + "\(probe.elapsedMs)ms): \(why); capturing anyway\n", stderr)
      }
    }
    // appForeground: derived from verifyActiveBundleId; nil when WDA
    // unreachable (omitted from JSON — shape unchanged for legacy callers).
    let appForeground = await WDASessionRepair.appForeground(requested: nil, env: env)

    if grid {
      // Capture CGImage → overlay → encode → write. On any failure, fall back
      // to the standard capture path and emit a warning.
      do {
        let udid = try await SimTools.resolveSimulator(sim, env: env)
        let info = try await SimTools.fetchScreenInfo(udid: udid, env: env)
        let cg = try await VisualTools.captureCGImage(simulator: udid, env: env)
        guard
          let gridded = xcforgeDrawPointGrid(
            on: cg,
            pointWidth: info.pointSize.width,
            pointHeight: info.pointSize.height,
            scale: info.scale
          )
        else {
          fputs("warning: grid overlay failed (could not allocate bitmap); falling back to ungridded image\n", stderr)
          try await VisualTools.captureScreenshot(
            simulator: sim, format: format, outputPath: output)
          let attrs = try FileManager.default.attributesOfItem(atPath: output)
          let fileSize = (attrs[.size] as? Int) ?? 0
          let result = ScreenshotResult(
            succeeded: true, path: output, format: format, sizeKB: fileSize / 1024,
            appForeground: appForeground)
          if useJSON {
            print(try WorkflowJSONRenderer.renderJSON(result))
          } else {
            print(ScreenshotRenderer.renderCapture(result))
          }
          return
        }
        if let data = xcforgeEncodeImage(gridded, format: format) {
          let parent = (output as NSString).deletingLastPathComponent
          if !parent.isEmpty {
            try FileManager.default.createDirectory(
              atPath: parent, withIntermediateDirectories: true)
          }
          try data.write(to: URL(fileURLWithPath: output))
        } else {
          fputs("warning: grid overlay encode failed; falling back to ungridded image\n", stderr)
          try await VisualTools.captureScreenshot(
            simulator: sim, format: format, outputPath: output)
        }
      } catch {
        fputs("warning: grid overlay failed (\(error)); falling back to ungridded image\n", stderr)
        try await VisualTools.captureScreenshot(
          simulator: sim, format: format, outputPath: output)
      }
    } else {
      try await VisualTools.captureScreenshot(
        simulator: sim,
        format: format,
        outputPath: output
      )
    }

    let attrs = try FileManager.default.attributesOfItem(atPath: output)
    let fileSize = (attrs[.size] as? Int) ?? 0
    let sizeKB = fileSize / 1024

    let result = ScreenshotResult(
      succeeded: true,
      path: output,
      format: format,
      sizeKB: sizeKB,
      appForeground: appForeground
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(ScreenshotRenderer.renderCapture(result))
    }
  }
}

// MARK: - Baseline

struct ScreenshotBaseline: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "baseline",
    abstract: "Capture a screenshot and save it as a named visual baseline."
  )

  @Option(help: "Baseline name (e.g. 'login-screen'). Used as filename.")
  var name: String

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Directory to store baselines. Default: visual-baselines")
  var baselineDir: String = "visual-baselines"

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let sim = try await env.session.resolveSimulator(simulator)

    // Ensure baseline directory exists
    try FileManager.default.createDirectory(
      atPath: baselineDir, withIntermediateDirectories: true
    )

    let baselinePath = "\(baselineDir)/\(VisualTools.sanitize(name)).png"

    // Capture screenshot as CGImage
    let cgImage = try await VisualTools.captureCGImage(simulator: sim)

    // Remove existing baseline if present
    let fm = FileManager.default
    if fm.fileExists(atPath: baselinePath) {
      try fm.removeItem(atPath: baselinePath)
    }

    // Save as PNG
    VisualTools.savePNG(image: cgImage, path: baselinePath)

    let attrs = try fm.attributesOfItem(atPath: baselinePath)
    let fileSize = (attrs[.size] as? Int) ?? 0
    let sizeKB = fileSize / 1024

    let result = ScreenshotResult(
      succeeded: true,
      path: baselinePath,
      format: "png",
      sizeKB: sizeKB
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(ScreenshotRenderer.renderBaseline(result))
    }
  }
}

// MARK: - Compare

struct ScreenshotCompare: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "compare",
    abstract: "Capture a screenshot and compare it against a saved visual baseline."
  )

  @Option(help: "Baseline name to compare against.")
  var name: String

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Max allowed diff percentage (0-100). Default: 0.5")
  var threshold: Double = 0.5

  @Option(help: "Directory where baselines are stored. Default: visual-baselines")
  var baselineDir: String = "visual-baselines"

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let sim = try await env.session.resolveSimulator(simulator)

    let sanitizedName = VisualTools.sanitize(name)
    let baselinePath = "\(baselineDir)/\(sanitizedName).png"
    let runId = UUID().uuidString.prefix(8)
    let currentPath = "/tmp/xcforge-visual-current-\(runId).png"
    let diffPath = "/tmp/xcforge-visual-diff-\(sanitizedName)-\(runId).png"

    // Check baseline exists
    guard FileManager.default.fileExists(atPath: baselinePath) else {
      throw ValidationError(
        "Baseline not found: \(baselinePath)\nRun 'xcforge screenshot baseline --name \(name)' first."
      )
    }

    // Capture current screenshot
    let currentImage = try await VisualTools.captureCGImage(simulator: sim)

    // Save current screenshot for reference
    VisualTools.savePNG(image: currentImage, path: currentPath)

    // Load baseline
    guard let baselineImage = VisualTools.loadCGImage(path: baselinePath) else {
      throw ValidationError("Failed to load baseline image: \(baselinePath)")
    }

    // Compare
    let comparison = VisualTools.pixelCompare(
      baseline: baselineImage, current: currentImage
    )

    // Save diff image if available
    var savedDiffPath: String? = nil
    if let diffImage = comparison.diffImage {
      VisualTools.savePNG(image: diffImage, path: diffPath)
      savedDiffPath = diffPath
    }

    let passed = comparison.diffPercent <= threshold

    let result = VisualCompareResult(
      passed: passed,
      diffPercent: comparison.diffPercent,
      threshold: threshold,
      changedPixels: comparison.changedPixels,
      totalPixels: comparison.totalPixels,
      baselinePath: baselinePath,
      currentPath: currentPath,
      diffPath: savedDiffPath
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(ScreenshotRenderer.renderCompare(result, name: name))
    }

    if !passed {
      throw ExitCode.failure
    }
  }
}
