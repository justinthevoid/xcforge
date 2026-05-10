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
        "Take a screenshot of a booted simulator and return the image inline. Automatically selects the fastest available capture method (native framebuffer <10ms, ScreenCaptureKit ~20ms, or simctl ~320ms fallback). Use after any UI interaction to verify the result visually. Simulator is auto-detected if omitted.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
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
        ]),
      ])
    )
  ]

  // MARK: - Input Types

  struct ScreenshotInput: Decodable {
    let simulator: String?
    let format: String?
    let grid: Bool?
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

    let start = CFAbsoluteTimeGetCurrent()

    // Grid mode: capture CGImage → overlay → encode → return inline.
    // On any failure during the overlay path, fall back to the ungridded path
    // and surface a warning rather than failing the call.
    if wantGrid {
      do {
        let udid = try await SimTools.resolveSimulator(sim, env: env)
        let info = try await SimTools.fetchScreenInfo(udid: udid, env: env)
        let cgImage = try await VisualTools.captureCGImage(simulator: udid, env: env)
        if let gridded = drawPointGrid(
          on: cgImage,
          pointWidth: info.pointSize.width,
          pointHeight: info.pointSize.height,
          scale: info.scale
        ), let encoded = encodeImage(gridded, format: format) {
          let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
          let mimeType = format.hasPrefix("jp") ? "image/jpeg" : "image/png"
          let pxW = gridded.width
          let pxH = gridded.height
          let ptW = Int(info.pointSize.width)
          let ptH = Int(info.pointSize.height)
          return .init(content: [
            .image(
              data: encoded.base64EncodedString(), mimeType: mimeType,
              annotations: nil, _meta: nil),
            .text(
              text:
                "\(ptW)×\(ptH) pt | \(pxW)x\(pxH) px | \(encoded.count / 1024)KB | \(elapsed)ms (grid)",
              annotations: nil, _meta: nil),
          ])
        }
        Log.warn("Grid overlay or encode failed; returning ungridded image")
      } catch {
        Log.warn("Grid overlay failed (\(error)); returning ungridded image")
      }
    }

    // Fast path: inline capture (macOS 14+)
    if #available(macOS 14.0, *) {
      do {
        let result = try await FramebufferCapture.captureInline(
          simulator: sim, format: format
        )
        let elapsed = String(
          format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        let mimeType = format.hasPrefix("jp") ? "image/jpeg" : "image/png"
        let ptInfo = result.pointWidth > 0 ? "\(result.pointWidth)×\(result.pointHeight) pt | " : ""
        return .init(content: [
          .image(
            data: result.base64, mimeType: mimeType, annotations: nil, _meta: nil),
          .text(
            text:
              "\(ptInfo)\(result.width)x\(result.height) px | \(result.dataSize / 1024)KB | \(elapsed)ms (\(result.method))",
            annotations: nil, _meta: nil),
        ])
      } catch {
        Log.warn("Inline screenshot failed, falling back to simctl: \(error)")
        return await simctlScreenshot(sim: sim, format: format, start: start, env: env)
      }
    }

    return await simctlScreenshot(sim: sim, format: format, start: start, env: env)
  }

  // MARK: - simctl Fallback (writes to file, returns path)

  private static func simctlScreenshot(
    sim: String, format: String, start: CFAbsoluteTime, env: Environment
  ) async -> CallTool.Result {
    let outputPath = "/tmp/xcf-screenshot.\(format)"
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
          // Best-effort point dimensions from Simulator window
          var ptInfo = ""
          if #available(macOS 14.0, *) {
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
              text: "\(ptInfo)\(data.count / 1024)KB | \(elapsed)ms (simctl)",
              annotations: nil, _meta: nil),
          ])
        }
        return .ok("Screenshot saved: \(outputPath) | \(elapsed)ms (simctl)")
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
    case "screenshot": return await screenshot(args, env: env)
    default: return nil
    }
  }
}
