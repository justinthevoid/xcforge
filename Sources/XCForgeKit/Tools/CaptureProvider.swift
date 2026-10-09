import CoreGraphics
import CoreText
import Foundation
import ImageIO
import MCP
import UniformTypeIdentifiers

enum ScreenshotTools {
  struct WorkflowCaptureResult: Sendable, Equatable {
    let availability: WorkflowEvidenceAvailability
    let unavailableReason: WorkflowEvidenceUnavailableReason?
    let reference: String?
    let source: String
    let detail: String?
  }

  public static let tools: [Tool] = [
    Tool(
      name: "screenshot",
      description:
        "Take a screenshot of a booted simulator and return the image inline. Automatically selects the fastest available capture method (native framebuffer <10ms, ScreenCaptureKit ~20ms, or simctl ~320ms fallback). Use after any UI interaction to verify the result visually. Simulator is auto-detected if omitted. device takes a physical device's screenshot instead.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"),
            "description": .string("Physical device name or UDID. Captures that device instead of a simulator."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "format": .object([
            "type": .string("string"),
            "description": .string("Image format: png or jpeg. Default: jpeg"),
          ]),
          "grid": .object([
            "type": .string("boolean"),
            "description": .string(
              "Overlay a point-coordinate grid (50pt minor lines, 100pt labeled). Useful for eyeballing tap coordinates. Default: false."
            ),
          ]),
          "waitFor": .object([
            "type": .string("string"),
            "description": .string(
              "Readiness signal(s), comma-separated (all must hold): `launch-complete`, `a11y:<id>`, `text:<substring>`. Gates the capture on a real signal (AXP-first, WDA fallback). Warn-only — never fails the screenshot."
            ),
          ]),
          "timeout": .object([
            "type": .string("number"),
            "description": .string(
              "Ceiling in seconds for `waitFor`. Capture happens the instant the signal holds. Default 20."
            ),
          ]),
          "crop": .object([
            "type": .string("string"),
            "description": .string(
              "Region to return, as x,y,width,height in device points (the coordinates taps use), e.g. 0,100,390,200."
            ),
          ]),
          "max_dimension": .object([
            "type": .string("integer"),
            "description": .string(
              "Shrink the image so its longer side is at most this many pixels. Saves tokens; the result says how many points one pixel covers."
            ),
          ]),
        ]),
      ])
    )
  ]

  // MARK: - Input Types

  struct ScreenshotInput: Decodable {
    let simulator: String?
    let format: String?
    let grid: Bool?
    let waitFor: String?
    let timeout: Double?
    let crop: String?
    let maxDimension: Int?

    enum CodingKeys: String, CodingKey {
      case simulator, format, grid, waitFor, timeout, crop
      case maxDimension = "max_dimension"
    }
  }

  static func screenshot(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(ScreenshotInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return await screenshotImpl(input, env: env)
    }
  }

  private static func screenshotImpl(_ input: ScreenshotInput, env: Environment) async
    -> CallTool.Result
  {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(input.simulator)
    } catch {
      return .fail("\(error)")
    }
    let format = input.format ?? "jpeg"
    let wantGrid = input.grid ?? false
    var crop: ScreenshotShaping.PointRect?
    if let spec = input.crop {
      guard let parsed = ScreenshotShaping.parseCrop(spec) else { return .fail(ScreenshotShaping.cropFormatHelp) }
      crop = parsed
    }
    if let maxDimension = input.maxDimension, maxDimension < ScreenshotShaping.minimumDimension {
      return .fail("max_dimension must be at least \(ScreenshotShaping.minimumDimension)")
    }

    // Optional readiness gate — warn-only, NEVER hard-fails the screenshot.
    var readinessNote = ""
    if let waitFor = input.waitFor, !waitFor.trimmingCharacters(in: .whitespaces).isEmpty {
      let parsed = ReadinessProbe.Signal.parseSpec(waitFor)
      let probe = await ReadinessProbe.waitReady(
        signals: parsed.signals,
        timeout: input.timeout ?? 20,
        specWasUnparseable: parsed.allUnparseable,
        simulator: input.simulator,
        env: env
      )
      if !probe.ready {
        let why = probe.reason ?? "signal(s) not satisfied before timeout"
        Log.warn(
          "screenshot readiness gate not satisfied (mode: \(probe.mode.rawValue)): \(why)")
        readinessNote = " | readiness:\(probe.mode.rawValue) not-ready"
      } else {
        readinessNote = " | readiness:\(probe.mode.rawValue)"
      }
    }

    // appForeground derived from verifyActiveBundleId vs the recorded active
    // bundle — `null` (omitted) when WDA is unreachable, never a false
    // negative. Surfaced in the trailing text so an agent can tell the app it
    // thinks it is driving is actually backgrounded.
    let appForeground = await WDASessionRepair.appForeground(requested: nil, env: env)
    let fgNote: String = {
      guard let appForeground else { return "" }
      return " | appForeground:\(appForeground)"
    }()
    let trailing = readinessNote + fgNote
    let landscape = await interfaceLandscape(env: env)

    let start = CFAbsoluteTimeGetCurrent()

    // Grid, crop or downscale: capture a CGImage at device pixels, then shape it. Grid alone
    // falls back to the ungridded fast path on failure; a crop or size the caller relies on
    // fails instead of silently returning something else.
    let shaping = crop != nil || input.maxDimension != nil
    if wantGrid || shaping {
      do {
        let udid = try await SimTools.resolveSimulator(sim, env: env)
        let info = try await SimTools.fetchScreenInfo(udid: udid, env: env)
        var image = try await VisualTools.captureCGImage(simulator: udid, env: env)
        let capturedWidth = image.width
        let capturedHeight = image.height
        let points = ScreenshotShaping.orientedPointSize(
          width: info.pointSize.width, height: info.pointSize.height, pixelWidth: image.width,
          pixelHeight: image.height)
        if wantGrid {
          if let gridded = drawPointGrid(
            on: image, pointWidth: points.width, pointHeight: points.height, scale: info.scale)
          {
            image = gridded
          } else {
            Log.warn("Grid overlay failed; returning the image without it")
          }
        }
        image = ScreenshotShaping.shape(image, crop: crop, scale: info.scale, maxDimension: input.maxDimension)
        guard let encoded = encodeImage(image, format: format) else {
          throw NSError(
            domain: "ScreenshotTools", code: 1, userInfo: [NSLocalizedDescriptionKey: "image encoding failed"])
        }
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        let mimeType = format.hasPrefix("jp") ? "image/jpeg" : "image/png"
        let shown = ScreenshotShaping.interfacePointSize(
          width: info.pointSize.width, height: info.pointSize.height, pixelWidth: capturedWidth,
          pixelHeight: capturedHeight, interfaceLandscape: landscape)
        let size = ScreenshotShaping.pointSizeText(
          width: Int(shown.width), height: Int(shown.height), imageRotated: shown.imageRotated)
        var parts = ["\(size) screen"]
        var shownPointWidth = points.width
        if let crop {
          parts.append("crop \(crop.description) pt")
          shownPointWidth = min(crop.width, points.width - crop.x)
        }
        parts.append("\(image.width)x\(image.height) px")
        if input.maxDimension != nil {
          let ratio = ScreenshotShaping.pointsPerPixel(outputWidth: image.width, croppedPointWidth: shownPointWidth)
          parts.append(String(format: "1 px = %.2f pt", ratio))
        }
        let steps = [wantGrid ? "grid" : nil, crop != nil ? "crop" : nil, input.maxDimension != nil ? "scaled" : nil]
        let mode = steps.compactMap { $0 }.joined(separator: ", ")
        parts.append("\(encoded.count / 1024)KB")
        parts.append("\(elapsed)ms (\(mode))")
        return .init(content: [
          .image(data: encoded.base64EncodedString(), mimeType: mimeType, annotations: nil, _meta: nil),
          .text(text: parts.joined(separator: " | ") + trailing, annotations: nil, _meta: nil),
        ])
      } catch {
        if shaping { return .fail("Screenshot failed: \(error)") }
        Log.warn("Grid overlay failed (\(error)); returning ungridded image")
      }
    }

    // Device points come from the simulator's screen, not the Simulator window, whose size
    // depends on its zoom.
    let screenInfo = await ScreenInfoCache.shared.info(for: sim, env: env)

    // Fast path: inline capture (macOS 14+)
    if #available(macOS 14.0, *) {
      do {
        let result = try await FramebufferCapture.captureInline(
          simulator: sim, format: format
        )
        let elapsed = String(
          format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        let mimeType = format.hasPrefix("jp") ? "image/jpeg" : "image/png"
        let ptInfo: String
        if let screenInfo {
          let shown = ScreenshotShaping.interfacePointSize(
            width: screenInfo.pointSize.width, height: screenInfo.pointSize.height, pixelWidth: result.width,
            pixelHeight: result.height, interfaceLandscape: landscape)
          let size = ScreenshotShaping.pointSizeText(
            width: Int(shown.width), height: Int(shown.height), imageRotated: shown.imageRotated)
          ptInfo = "\(size) | "
        } else {
          ptInfo = result.pointWidth > 0 ? "\(result.pointWidth)×\(result.pointHeight) pt | " : ""
        }
        return .init(content: [
          .image(
            data: result.base64, mimeType: mimeType, annotations: nil, _meta: nil),
          .text(
            text:
              "\(ptInfo)\(result.width)x\(result.height) px | \(result.dataSize / 1024)KB | \(elapsed)ms (\(result.method))\(trailing)",
            annotations: nil, _meta: nil),
        ])
      } catch {
        Log.warn("Inline screenshot failed, falling back to simctl: \(error)")
        return await simctlScreenshot(
          sim: sim, format: format, start: start, trailing: trailing, screenInfo: screenInfo,
          landscape: landscape, env: env)
      }
    }

    return await simctlScreenshot(
      sim: sim, format: format, start: start, trailing: trailing, screenInfo: screenInfo, landscape: landscape,
      env: env)
  }

  /// Whether the app's interface is landscape, asked of WDA only when it is already running
  /// (a screenshot never starts WDA). Nil when unknown.
  static func interfaceLandscape(env: Environment) async -> Bool? {
    guard await env.wdaClient.isHealthy(), let value = try? await env.wdaClient.getOrientation() else {
      return nil
    }
    let orientation = IndigoHIDClient.Orientation(wdaValue: value)
    return orientation == .landscapeLeft || orientation == .landscapeRight
  }

  // MARK: - simctl Fallback (writes to file, returns path)

  private static func simctlScreenshot(
    sim: String, format: String, start: CFAbsoluteTime, trailing: String, screenInfo: SimTools.ScreenInfo?,
    landscape: Bool?, env: Environment
  ) async -> CallTool.Result {
    let outputPath = ScreenshotShaping.uniquePath(format: format)
    do {
      let result = try await env.shell.xcrun(
        timeout: 15, "simctl", "io", sim, "screenshot",
        "--type=\(format)",
        outputPath
      )
      let elapsed = String(
        format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)

      if result.succeeded {
        // Read file and return inline
        if let data = FileManager.default.contents(atPath: outputPath) {
          let mimeType = format.hasPrefix("jp") ? "image/jpeg" : "image/png"
          defer { try? FileManager.default.removeItem(atPath: outputPath) }
          var ptInfo = ""
          if let screenInfo {
            let pixels = CGImageSourceCreateWithData(data as CFData, nil).flatMap {
              CGImageSourceCreateImageAtIndex($0, 0, nil)
            }
            let shown = ScreenshotShaping.interfacePointSize(
              width: screenInfo.pointSize.width, height: screenInfo.pointSize.height,
              pixelWidth: pixels?.width ?? 0, pixelHeight: pixels?.height ?? 1, interfaceLandscape: landscape)
            let size = ScreenshotShaping.pointSizeText(
              width: Int(shown.width), height: Int(shown.height), imageRotated: shown.imageRotated)
            ptInfo = "\(size) | "
          } else if #available(macOS 14.0, *) {
            if let window = try? await FramebufferCapture.findSimulatorWindow(simulator: sim) {
              let ptW = Int(window.frame.width)
              let ptH = Int(window.frame.height)
              if ptW > 0 { ptInfo = "\(ptW)×\(ptH) pt | " }
            }
          }
          return .init(content: [
            .image(
              data: data.base64EncodedString(), mimeType: mimeType,
              annotations: nil, _meta: nil),
            .text(
              text: "\(ptInfo)\(data.count / 1024)KB | \(elapsed)ms (simctl)\(trailing)",
              annotations: nil, _meta: nil),
          ])
        }
        return .ok("Screenshot saved: \(outputPath) | \(elapsed)ms (simctl)\(trailing)")
      }
      return .fail("Screenshot failed: \(result.stderr)")
    } catch {
      return .fail("Error: \(error)")
    }
  }

  static func captureWorkflowScreenshot(
    simulatorUDID: String,
    outputURL: URL,
    format: String = "png"
  ) async -> WorkflowCaptureResult {
    do {
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )
    } catch {
      return WorkflowCaptureResult(
        availability: .unavailable,
        unavailableReason: .executionFailed,
        reference: nil,
        source: "xcforge.runtime_screenshot",
        detail: "xcforge could not prepare the screenshot artifact path: \(error)"
      )
    }

    if #available(macOS 14.0, *) {
      do {
        let capture = try await FramebufferCapture.captureInline(
          simulator: simulatorUDID,
          format: format
        )
        guard let data = Data(base64Encoded: capture.base64) else {
          return WorkflowCaptureResult(
            availability: .unavailable,
            unavailableReason: .executionFailed,
            reference: nil,
            source: "xcforge.runtime_screenshot.\(capture.method)",
            detail:
              "xcforge captured a screenshot frame but could not decode the encoded image data."
          )
        }
        try data.write(to: outputURL, options: .atomic)
        return WorkflowCaptureResult(
          availability: .available,
          unavailableReason: nil,
          reference: outputURL.path,
          source: "xcforge.runtime_screenshot.\(capture.method)",
          detail: nil
        )
      } catch {
        return await simctlWorkflowScreenshot(
          simulatorUDID: simulatorUDID,
          outputURL: outputURL,
          format: format,
          priorError: error
        )
      }
    }

    return await simctlWorkflowScreenshot(
      simulatorUDID: simulatorUDID,
      outputURL: outputURL,
      format: format,
      priorError: nil
    )
  }

  private static func simctlWorkflowScreenshot(
    simulatorUDID: String,
    outputURL: URL,
    format: String,
    priorError: Error?
  ) async -> WorkflowCaptureResult {
    do {
      let result = try await Shell.xcrun(
        timeout: 15,
        "simctl",
        "io",
        simulatorUDID,
        "screenshot",
        "--type=\(format)",
        outputURL.path
      )

      if result.succeeded, FileManager.default.fileExists(atPath: outputURL.path) {
        return WorkflowCaptureResult(
          availability: .available,
          unavailableReason: nil,
          reference: outputURL.path,
          source: "simctl.io.screenshot",
          detail: nil
        )
      }

      let message = bestFailureDetail(
        stdout: result.stdout, stderr: result.stderr, priorError: priorError)
      return WorkflowCaptureResult(
        availability: .unavailable,
        unavailableReason: unavailableReason(for: message),
        reference: nil,
        source: "simctl.io.screenshot",
        detail: message
      )
    } catch {
      let message = bestFailureDetail(stdout: nil, stderr: nil, priorError: error)
      return WorkflowCaptureResult(
        availability: .unavailable,
        unavailableReason: unavailableReason(for: message),
        reference: nil,
        source: "simctl.io.screenshot",
        detail: message
      )
    }
  }

  private static func bestFailureDetail(stdout: String?, stderr: String?, priorError: Error?)
    -> String
  {
    let stderr = stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let stderr, !stderr.isEmpty {
      return stderr
    }
    let stdout = stdout?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let stdout, !stdout.isEmpty {
      return stdout
    }
    if let priorError {
      return "\(priorError)"
    }
    return "xcforge could not capture a simulator screenshot for this runtime attempt."
  }

  private static func unavailableReason(for message: String) -> WorkflowEvidenceUnavailableReason {
    let lowered = message.lowercased()
    if lowered.contains("permission")
      || lowered.contains("screen recording")
      || lowered.contains("screen capture")
      || lowered.contains("framebuffer")
      || lowered.contains("capture is unsupported")
      || lowered.contains("no booted device")
      || lowered.contains("no devices are booted")
      || lowered.contains("simulator must be booted")
    {
      return .unsupported
    }
    return .executionFailed
  }

  // MARK: - Grid Overlay

  /// Draw a point-coordinate grid over the given image. Minor lines every 50pt,
  /// labeled major lines every 100pt. Drawing is performed in pixel space; the
  /// `scale` factor maps point spacing to the image's native pixel dimensions.
  /// Returns nil when the overlay cannot be applied (invalid geometry, allocation
  /// failure, or unsupported image dimensions). Callers should fall back to the
  /// ungridded image and surface a warning.
  static func drawPointGrid(
    on image: CGImage, pointWidth: Double, pointHeight: Double, scale: Double
  ) -> CGImage? {
    let pixelWidth = image.width
    let pixelHeight = image.height
    guard pixelWidth > 0, pixelHeight > 0, scale > 0, pointWidth > 0, pointHeight > 0 else {
      return nil
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard
      let ctx = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: bitmapInfo
      )
    else { return nil }

    // Draw the source image into the bitmap. Origin is bottom-left in CG.
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

    let minorStepPt: Double = 50
    let majorStepPt: Double = 100
    let minorPxX = minorStepPt * scale
    let minorPxY = minorStepPt * scale
    let lineWidthMinor: CGFloat = max(1, CGFloat(scale) * 0.5)
    let lineWidthMajor: CGFloat = max(1, CGFloat(scale))

    // Minor (50pt) lines — light gray, semi-transparent.
    ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.35)
    ctx.setLineWidth(lineWidthMinor)
    var x = minorPxX
    while x < Double(pixelWidth) {
      ctx.move(to: CGPoint(x: x, y: 0))
      ctx.addLine(to: CGPoint(x: x, y: Double(pixelHeight)))
      x += minorPxX
    }
    var y = minorPxY
    while y < Double(pixelHeight) {
      ctx.move(to: CGPoint(x: 0, y: y))
      ctx.addLine(to: CGPoint(x: Double(pixelWidth), y: y))
      y += minorPxY
    }
    ctx.strokePath()

    // Major (100pt) lines — magenta, more opaque.
    ctx.setStrokeColor(red: 1, green: 0, blue: 1, alpha: 0.7)
    ctx.setLineWidth(lineWidthMajor)
    let majorPxX = majorStepPt * scale
    let majorPxY = majorStepPt * scale
    var mx = majorPxX
    while mx < Double(pixelWidth) {
      ctx.move(to: CGPoint(x: mx, y: 0))
      ctx.addLine(to: CGPoint(x: mx, y: Double(pixelHeight)))
      mx += majorPxX
    }
    var my = majorPxY
    while my < Double(pixelHeight) {
      ctx.move(to: CGPoint(x: 0, y: my))
      ctx.addLine(to: CGPoint(x: Double(pixelWidth), y: my))
      my += majorPxY
    }
    ctx.strokePath()

    // Labels every 100pt along top + left edges (in points).
    let fontSize = max(10, 8 * scale)
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
    let labelColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
    let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.85)

    func drawLabel(_ text: String, atPixel point: CGPoint) {
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: labelColor,
      ]
      let attributed = NSAttributedString(string: text, attributes: attrs)
      let line = CTLineCreateWithAttributedString(attributed)

      // Drop shadow for legibility on bright backgrounds.
      ctx.saveGState()
      ctx.setShadow(
        offset: CGSize(width: 1, height: -1), blur: 2, color: shadowColor)
      ctx.textPosition = point
      CTLineDraw(line, ctx)
      ctx.restoreGState()
    }

    // X labels (top edge). CG origin is bottom-left; place near top.
    let topY = Double(pixelHeight) - fontSize - 4
    var labelX = majorPxX
    var ptX = Int(majorStepPt)
    while labelX < Double(pixelWidth) {
      drawLabel("\(ptX)", atPixel: CGPoint(x: labelX + 4, y: topY))
      labelX += majorPxX
      ptX += Int(majorStepPt)
    }
    // Y labels (left edge), in points from top.
    var labelY = majorPxY
    var ptY = Int(majorStepPt)
    while labelY < Double(pixelHeight) {
      // Convert "point Y from top" to CG y (from bottom).
      let cgY = Double(pixelHeight) - labelY - fontSize
      drawLabel("\(ptY)", atPixel: CGPoint(x: 4, y: cgY))
      labelY += majorPxY
      ptY += Int(majorStepPt)
    }

    return ctx.makeImage()
  }

  /// Encode a CGImage as PNG or JPEG bytes.
  static func encodeImage(_ image: CGImage, format: String) -> Data? {
    let utType: CFString =
      format.hasPrefix("jp") ? UTType.jpeg.identifier as CFString : UTType.png.identifier as CFString
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, utType, 1, nil) else { return nil }
    let options: CFDictionary =
      format.hasPrefix("jp")
      ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
      : [:] as CFDictionary
    CGImageDestinationAddImage(dest, image, options)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
  }
}

// MARK: - Public CLI Helpers

/// Public wrapper around the internal grid overlay so the CLI can apply it
/// to a `CGImage` without exposing the entire `ScreenshotTools` namespace.
public func xcforgeDrawPointGrid(
  on image: CGImage, pointWidth: Double, pointHeight: Double, scale: Double
) -> CGImage? {
  ScreenshotTools.drawPointGrid(
    on: image, pointWidth: pointWidth, pointHeight: pointHeight, scale: scale)
}

/// Public wrapper for encoding a `CGImage` as PNG/JPEG bytes.
public func xcforgeEncodeImage(_ image: CGImage, format: String) -> Data? {
  ScreenshotTools.encodeImage(image, format: format)
}

extension ScreenshotTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "screenshot":
      // A physical device: devicectl capture, falling back to the device's WDA.
      if let device = args?["device"] {
        return await DeviceTools.dispatch("device_screenshot", ["device": device], env: env)
          ?? .fail("device screenshots are unavailable")
      }
      return await screenshot(args, env: env)
    default: return nil
    }
  }
}
