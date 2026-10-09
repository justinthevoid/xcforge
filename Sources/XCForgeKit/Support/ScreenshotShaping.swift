import CoreGraphics
import Foundation

/// Cropping and downscaling a simulator screenshot, in the device points agents tap with.
public enum ScreenshotShaping {
  /// A region of the screen in device points.
  public struct PointRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }

    public var description: String {
      [x, y, width, height].map { String(Int($0.rounded())) }.joined(separator: ",")
    }
  }

  /// Smallest `max_dimension` that still gives a readable image.
  public static let minimumDimension = 64

  public static let cropFormatHelp = "crop must be x,y,width,height in points, e.g. 0,100,390,200"

  /// Parse `x,y,width,height` (points). Width and height must be positive.
  public static func parseCrop(_ spec: String) -> PointRect? {
    let parts = spec.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 4, let x = parts[0], let y = parts[1], let w = parts[2], let h = parts[3],
      x >= 0, y >= 0, w > 0, h > 0
    else { return nil }
    return PointRect(x: x, y: y, width: w, height: h)
  }

  /// The crop in image pixels, clipped to the image. Nil when nothing of it is on the image.
  public static func pixelRect(_ crop: PointRect, scale: Double, imageWidth: Int, imageHeight: Int) -> CGRect? {
    let rect = CGRect(x: crop.x * scale, y: crop.y * scale, width: crop.width * scale, height: crop.height * scale)
      .integral
      .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    return rect.isNull || rect.isEmpty ? nil : rect
  }

  /// Output size for an image whose longer side must not exceed `maxDimension`.
  public static func scaledSize(width: Int, height: Int, maxDimension: Int) -> (width: Int, height: Int) {
    guard maxDimension > 0, max(width, height) > maxDimension else { return (width, height) }
    let factor = Double(maxDimension) / Double(max(width, height))
    return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
  }

  /// Crop to `crop` (points, using the screen `scale`), then shrink so the longer side is at
  /// most `maxDimension` pixels. Returns the original image when a step can't be done.
  public static func shape(_ image: CGImage, crop: PointRect?, scale: Double, maxDimension: Int?) -> CGImage {
    var result = image
    if let crop, let rect = pixelRect(crop, scale: scale, imageWidth: image.width, imageHeight: image.height),
      let cropped = image.cropping(to: rect)
    {
      result = cropped
    }
    if let maxDimension {
      result = downscale(result, maxDimension: maxDimension)
    }
    return result
  }

  public static func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
    let size = scaledSize(width: image.width, height: image.height, maxDimension: maxDimension)
    guard size.width != image.width || size.height != image.height else { return image }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
      let ctx = CGContext(
        data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    return ctx.makeImage() ?? image
  }

  /// A fresh path per capture, so parallel agents and runs never overwrite each other's image.
  public static func uniquePath(format: String, directory: String = NSTemporaryDirectory()) -> String {
    let name = "xcforge-screenshot-\(UUID().uuidString.prefix(8).lowercased()).\(format)"
    return (directory as NSString).appendingPathComponent(name)
  }

  /// The screen's point size turned to match the captured image: simctl reports the portrait
  /// size, but a landscape capture is wider than tall.
  public static func orientedPointSize(
    width: Double, height: Double, pixelWidth: Int, pixelHeight: Int
  ) -> (width: Double, height: Double) {
    let imageLandscape = pixelWidth > pixelHeight
    let sizeLandscape = width > height
    return imageLandscape == sizeLandscape ? (width, height) : (height, width)
  }

  /// The point size an agent taps in: the interface's orientation when WDA knows it, else the
  /// image's. The simulator framebuffer stays portrait when the app rotates, so a landscape app
  /// captures as a portrait image; `imageRotated` says so.
  public static func interfacePointSize(
    width: Double, height: Double, pixelWidth: Int, pixelHeight: Int, interfaceLandscape: Bool?
  ) -> (width: Double, height: Double, imageRotated: Bool) {
    let image = orientedPointSize(width: width, height: height, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    guard let interfaceLandscape else { return (image.width, image.height, false) }
    let long = max(width, height)
    let short = min(width, height)
    let imageLandscape = pixelWidth > pixelHeight
    return interfaceLandscape
      ? (long, short, !imageLandscape)
      : (short, long, imageLandscape)
  }

  /// "402×874 pt", plus a note when the image is turned relative to the interface.
  public static func pointSizeText(width: Int, height: Int, imageRotated: Bool) -> String {
    let size = "\(width)×\(height) pt"
    return imageRotated ? size + " (interface rotated; image is in framebuffer orientation)" : size
  }

  /// How many device points one output pixel covers, for mapping a downscaled image back to taps.
  public static func pointsPerPixel(outputWidth: Int, croppedPointWidth: Double) -> Double {
    guard outputWidth > 0 else { return 0 }
    return croppedPointWidth / Double(outputWidth)
  }
}

/// Screen geometry per simulator, so the fast screenshot path can report device points
/// without three `simctl getenv` calls per capture.
actor ScreenInfoCache {
  static let shared = ScreenInfoCache()
  private var byUDID: [String: SimTools.ScreenInfo] = [:]

  func info(for simulator: String, env: Environment) async -> SimTools.ScreenInfo? {
    if let cached = byUDID[simulator] { return cached }
    guard let info = try? await SimTools.fetchScreenInfo(udid: simulator, env: env) else { return nil }
    // "booted" can mean a different device next time; only cache real UDIDs.
    if simulator != "booted" { byUDID[simulator] = info }
    return info
  }
}
