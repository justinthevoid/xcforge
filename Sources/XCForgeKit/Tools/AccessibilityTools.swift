import CoreGraphics
import Foundation
import MCP

/// Tools for automated accessibility and localization checks.
/// Renders the app across Dynamic Type sizes or locales, screenshots each,
/// and detects layout issues (truncation, overlap, RTL breaks).
public enum AccessibilityTools {
  public static let tools: [Tool] = [
    Tool(
      name: "accessibility_check",
      description:
        "Render the current app screen across multiple Dynamic Type content size categories and detect truncation or layout issues. Takes a screenshot at each size and compares against the base size.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."
            ),
          ]),
          "sizes": .object([
            "type": .string("string"),
            "description": .string(
              "Comma-separated content size categories to test. Default: 'UICTContentSizeCategoryXS,UICTContentSizeCategoryL,UICTContentSizeCategoryXXXL,UICTContentSizeCategoryAccessibilityXXXL'. Use 'all' for all 12 categories."
            ),
          ]),
          "threshold": .object([
            "type": .string("number"),
            "description": .string(
              "Max allowed diff % between base and each size. Default: 5.0"
            ),
          ]),
          "settle_time": .object([
            "type": .string("number"),
            "description": .string(
              "Seconds to wait after setting size before screenshot. Default: 1.5"
            ),
          ]),
        ]),
        "required": .array([]),
      ])
    ),
    Tool(
      name: "localization_check",
      description:
        "Render the current app screen across multiple languages/locales and detect layout breaks. Supports RTL languages (Arabic, Hebrew). Takes a screenshot at each locale and compares against the base.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."
            ),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string(
              "App bundle identifier. Auto-detected from last build if omitted."
            ),
          ]),
          "locales": .object([
            "type": .string("string"),
            "description": .string(
              "Comma-separated locale identifiers. Default: 'en,de,ja,ar,he'. Use 'all' for common set of 10 locales."
            ),
          ]),
          "threshold": .object([
            "type": .string("number"),
            "description": .string(
              "Max allowed diff % between base and each locale. Default: 10.0 (locale changes naturally shift more pixels)"
            ),
          ]),
          "settle_time": .object([
            "type": .string("number"),
            "description": .string(
              "Seconds to wait after relaunching with new locale. Default: 3.0"
            ),
          ]),
        ]),
        "required": .array([]),
      ])
    ),
  ]

  // MARK: - Content Size Categories

  /// All Dynamic Type content size categories (smallest → largest)
  public static let allSizeCategories = [
    "UICTContentSizeCategoryXS",
    "UICTContentSizeCategoryS",
    "UICTContentSizeCategoryM",
    "UICTContentSizeCategoryL",  // system default
    "UICTContentSizeCategoryXL",
    "UICTContentSizeCategoryXXL",
    "UICTContentSizeCategoryXXXL",
    "UICTContentSizeCategoryAccessibilityM",
    "UICTContentSizeCategoryAccessibilityL",
    "UICTContentSizeCategoryAccessibilityXL",
    "UICTContentSizeCategoryAccessibilityXXL",
    "UICTContentSizeCategoryAccessibilityXXXL",
  ]

  public static let defaultSizeCategories = [
    "UICTContentSizeCategoryXS",
    "UICTContentSizeCategoryL",
    "UICTContentSizeCategoryXXXL",
    "UICTContentSizeCategoryAccessibilityXXXL",
  ]

  /// Short display names for categories
  public static func shortName(for category: String) -> String {
    category
      .replacingOccurrences(of: "UICTContentSizeCategory", with: "")
      .replacingOccurrences(of: "Accessibility", with: "A11y-")
  }

  // MARK: - Locales

  public static let allLocales = [
    "en", "de", "fr", "es", "ja", "zh-Hans", "ko", "ar", "he", "pt-BR",
  ]

  public static let defaultLocales = ["en", "de", "ja", "ar", "he"]

  public static let rtlLocales: Set<String> = ["ar", "he", "ur", "fa"]

  // MARK: - Input Types

  struct AccessibilityInput: Decodable {
    let simulator: String?
    let sizes: String?
    let threshold: Double?
    let settle_time: Double?
  }

  struct LocalizationInput: Decodable {
    let simulator: String?
    let bundle_id: String?
    let locales: String?
    let threshold: Double?
    let settle_time: Double?
  }

  // MARK: - Accessibility Check

  static func accessibilityCheck(_ args: [String: Value]?, env: Environment) async
    -> CallTool.Result
  {
    switch ToolInput.decode(AccessibilityInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return await accessibilityCheckImpl(input, env: env)
    }
  }

  private static func accessibilityCheckImpl(_ input: AccessibilityInput, env: Environment) async
    -> CallTool.Result
  {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(input.simulator)
    } catch {
      return .fail("\(error)")
    }

    let threshold = input.threshold ?? 5.0
    let settleTime = input.settle_time ?? 1.5

    // Parse sizes
    let sizes: [String]
    if let sizesStr = input.sizes, !sizesStr.isEmpty {
      if sizesStr.lowercased() == "all" {
        sizes = allSizeCategories
      } else {
        sizes = sizesStr.split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespaces)
        }
      }
    } else {
      sizes = defaultSizeCategories
    }

    guard sizes.count >= 2 else {
      return .fail("Need at least 2 size categories to compare.")
    }

    let runId = String(UUID().uuidString.prefix(8))
    let start = CFAbsoluteTimeGetCurrent()

    // Save current preference so we can restore it
    let originalSize = await getCurrentContentSize(sim: sim, env: env)

    var screenshots: [(category: String, image: CGImage, path: String)] = []
    var errors: [(category: String, error: String)] = []

    // Screenshot each size category
    for category in sizes {
      // Set the content size via simctl
      do {
        let setResult = try await env.shell.xcrun(
          timeout: 10, "simctl", "ui", sim,
          "content_size", category
        )
        guard setResult.succeeded else {
          errors.append((category, "Failed to set size: \(setResult.stderr)"))
          continue
        }
      } catch {
        errors.append((category, "simctl error: \(error)"))
        continue
      }

      // Wait for UI to settle
      try? await Task.sleep(nanoseconds: UInt64(settleTime * 1_000_000_000))

      // Take screenshot
      let path = "/tmp/xcforge-a11y-\(runId)-\(VisualTools.sanitize(category)).png"
      do {
        let img = try await VisualTools.captureCGImage(simulator: sim, env: env)
        VisualTools.savePNG(image: img, path: path)
        screenshots.append((category, img, path))
      } catch {
        errors.append((category, "Screenshot failed: \(error)"))
      }
    }

    // Restore original size
    if let original = originalSize {
      _ = try? await env.shell.xcrun(timeout: 10, "simctl", "ui", sim, "content_size", original)
    } else {
      _ = try? await env.shell.xcrun(
        timeout: 10, "simctl", "ui", sim,
        "content_size", "UICTContentSizeCategoryL"
      )
    }

    guard screenshots.count >= 2 else {
      return .fail(
        "Only captured \(screenshots.count) screenshots. Need 2+.\n"
          + errors.map { "\($0.category): \($0.error)" }.joined(separator: "\n")
      )
    }

    // Compare each against the base (first screenshot)
    let base = screenshots[0]
    var results: [SizeCheckResult] = []

    for ss in screenshots {
      if ss.category == base.category {
        results.append(
          SizeCheckResult(
            category: ss.category,
            shortName: shortName(for: ss.category),
            width: ss.image.width, height: ss.image.height,
            diffPercent: 0, passed: true, isBase: true,
            screenshotPath: ss.path, diffPath: nil
          ))
        continue
      }

      let cmp = VisualTools.pixelCompare(baseline: base.image, current: ss.image)
      let passed = cmp.diffPercent <= threshold

      var diffPath: String?
      if let diffImg = cmp.diffImage, !passed {
        let dp = "/tmp/xcforge-a11y-diff-\(runId)-\(VisualTools.sanitize(ss.category)).png"
        VisualTools.savePNG(image: diffImg, path: dp)
        diffPath = dp
      }

      results.append(
        SizeCheckResult(
          category: ss.category,
          shortName: shortName(for: ss.category),
          width: ss.image.width, height: ss.image.height,
          diffPercent: cmp.diffPercent, passed: passed, isBase: false,
          screenshotPath: ss.path, diffPath: diffPath
        ))
    }

    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    let allPassed = results.allSatisfy(\.passed)

    return buildAccessibilityReport(
      results: results, errors: errors, threshold: threshold,
      elapsed: elapsed, allPassed: allPassed
    )
  }

  // MARK: - Localization Check

  static func localizationCheck(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(LocalizationInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return await localizationCheckImpl(input, env: env)
    }
  }

  private static func localizationCheckImpl(_ input: LocalizationInput, env: Environment) async
    -> CallTool.Result
  {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(input.simulator)
    } catch {
      return .fail("\(error)")
    }

    let threshold = input.threshold ?? 10.0
    let settleTime = input.settle_time ?? 3.0

    // Resolve bundle ID
    let bundleId: String
    if let bid = input.bundle_id, !bid.isEmpty {
      bundleId = bid
    } else if let cached = await env.session.bundleId {
      bundleId = cached
    } else {
      return .fail(
        "No bundle_id provided and none cached from a previous build. Provide bundle_id.")
    }

    // Parse locales
    let locales: [String]
    if let localesStr = input.locales, !localesStr.isEmpty {
      if localesStr.lowercased() == "all" {
        locales = allLocales
      } else {
        locales = localesStr.split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespaces)
        }
      }
    } else {
      locales = defaultLocales
    }

    guard locales.count >= 2 else {
      return .fail("Need at least 2 locales to compare.")
    }

    let runId = String(UUID().uuidString.prefix(8))
    let start = CFAbsoluteTimeGetCurrent()

    var screenshots: [(locale: String, image: CGImage, path: String)] = []
    var errors: [(locale: String, error: String)] = []

    // For each locale: terminate app, relaunch with locale override, screenshot
    for locale in locales {
      // Terminate current app instance
      _ = try? await env.shell.xcrun(timeout: 5, "simctl", "terminate", sim, bundleId)
      try? await Task.sleep(nanoseconds: 500_000_000)

      // Launch with locale and language overrides
      let langCode = locale.split(separator: "-").first.map(String.init) ?? locale
      do {
        let launchResult = try await env.shell.xcrun(
          timeout: 15, "simctl", "launch", sim, bundleId,
          "-AppleLanguages", "(\(langCode))",
          "-AppleLocale", locale,
          "-AppleTextDirection", rtlLocales.contains(langCode) ? "YES" : "NO"
        )
        guard launchResult.succeeded else {
          errors.append((locale, "Launch failed: \(launchResult.stderr)"))
          continue
        }
      } catch {
        errors.append((locale, "Launch error: \(error)"))
        continue
      }

      // Wait for app to settle
      try? await Task.sleep(nanoseconds: UInt64(settleTime * 1_000_000_000))

      // Take screenshot
      let path = "/tmp/xcforge-l10n-\(runId)-\(VisualTools.sanitize(locale)).png"
      do {
        let img = try await VisualTools.captureCGImage(simulator: sim, env: env)
        VisualTools.savePNG(image: img, path: path)
        screenshots.append((locale, img, path))
      } catch {
        errors.append((locale, "Screenshot failed: \(error)"))
      }
    }

    guard screenshots.count >= 2 else {
      return .fail(
        "Only captured \(screenshots.count) screenshots. Need 2+.\n"
          + errors.map { "\($0.locale): \($0.error)" }.joined(separator: "\n")
      )
    }

    // Compare each against the base locale (first)
    let base = screenshots[0]
    var results: [LocaleCheckResult] = []

    for ss in screenshots {
      let isRTL = rtlLocales.contains(
        ss.locale.split(separator: "-").first.map(String.init) ?? ss.locale
      )

      if ss.locale == base.locale {
        results.append(
          LocaleCheckResult(
            locale: ss.locale, isRTL: isRTL,
            width: ss.image.width, height: ss.image.height,
            diffPercent: 0, passed: true, isBase: true,
            screenshotPath: ss.path, diffPath: nil
          ))
        continue
      }

      let cmp = VisualTools.pixelCompare(baseline: base.image, current: ss.image)
      let passed = cmp.diffPercent <= threshold

      var diffPath: String?
      if let diffImg = cmp.diffImage, !passed {
        let dp = "/tmp/xcforge-l10n-diff-\(runId)-\(VisualTools.sanitize(ss.locale)).png"
        VisualTools.savePNG(image: diffImg, path: dp)
        diffPath = dp
      }

      results.append(
        LocaleCheckResult(
          locale: ss.locale, isRTL: isRTL,
          width: ss.image.width, height: ss.image.height,
          diffPercent: cmp.diffPercent, passed: passed, isBase: false,
          screenshotPath: ss.path, diffPath: diffPath
        ))
    }

    // Relaunch with first locale to restore
    _ = try? await env.shell.xcrun(timeout: 5, "simctl", "terminate", sim, bundleId)
    let baseLang = locales[0].split(separator: "-").first.map(String.init) ?? locales[0]
    _ = try? await env.shell.xcrun(
      timeout: 15, "simctl", "launch", sim, bundleId,
      "-AppleLanguages", "(\(baseLang))",
      "-AppleLocale", locales[0]
    )

    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    let allPassed = results.allSatisfy(\.passed)

    return buildLocalizationReport(
      results: results, errors: errors, threshold: threshold,
      elapsed: elapsed, allPassed: allPassed
    )
  }

  // MARK: - Result Types

  struct SizeCheckResult {
    let category: String
    let shortName: String
    let width: Int
    let height: Int
    let diffPercent: Double
    let passed: Bool
    let isBase: Bool
    let screenshotPath: String
    let diffPath: String?
  }

  struct LocaleCheckResult {
    let locale: String
    let isRTL: Bool
    let width: Int
    let height: Int
    let diffPercent: Double
    let passed: Bool
    let isBase: Bool
    let screenshotPath: String
    let diffPath: String?
  }

  // MARK: - Public CLI Helpers

  /// Set the Dynamic Type content size category on a simulator.
  public static func setContentSize(_ category: String, simulator: String) async throws {
    let result = try await Shell.xcrun(
      timeout: 10, "simctl", "ui", simulator, "content_size", category
    )
    guard result.succeeded else {
      throw NSError(
        domain: "AccessibilityTools", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to set content size: \(result.stderr)"]
      )
    }
  }

  /// Terminate an app, then relaunch it with a specific locale/language override.
  public static func relaunchWithLocale(
    _ locale: String, bundleId: String, simulator: String, isRTL: Bool
  ) async throws {
    _ = try? await Shell.xcrun(timeout: 5, "simctl", "terminate", simulator, bundleId)
    try? await Task.sleep(nanoseconds: 500_000_000)

    let langCode = locale.split(separator: "-").first.map(String.init) ?? locale
    let result = try await Shell.xcrun(
      timeout: 15, "simctl", "launch", simulator, bundleId,
      "-AppleLanguages", "(\(langCode))",
      "-AppleLocale", locale,
      "-AppleTextDirection", isRTL ? "YES" : "NO"
    )
    guard result.succeeded else {
      throw NSError(
        domain: "AccessibilityTools", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Launch failed: \(result.stderr)"]
      )
    }
  }

  // MARK: - Helpers

  private static func getCurrentContentSize(sim: String, env: Environment) async -> String? {
    // Try to read the current content size preference
    guard
      let result = try? await env.shell.xcrun(
        timeout: 5, "simctl", "spawn", sim,
        "defaults", "read", ".GlobalPreferences", "UIPreferredContentSizeCategoryName"
      ), result.succeeded
    else {
      return nil
    }
    let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  // MARK: - Report Building

  private static func buildAccessibilityReport(
    results: [SizeCheckResult], errors: [(category: String, error: String)],
    threshold: Double, elapsed: String, allPassed: Bool
  ) -> CallTool.Result {
    let status = allPassed ? "PASS" : "FAIL"
    var report: [String] = []
    report.append("[\(status)] Dynamic Type Accessibility Check (\(elapsed)s)")
    report.append("Threshold: \(String(format: "%.1f", threshold))%")
    report.append("Sizes tested: \(results.count)")
    report.append("")

    for r in results {
      let icon: String
      if r.isBase {
        icon = "[BASE]"
      } else {
        icon = r.passed ? "[OK]" : "[FAIL]"
      }
      let diffStr = r.isBase ? "—" : String(format: "%.2f%%", r.diffPercent)
      report.append("  \(icon) \(r.shortName) (\(r.width)x\(r.height)) diff: \(diffStr)")
      if let dp = r.diffPath {
        report.append("       Diff: \(dp)")
      }
    }

    if !errors.isEmpty {
      report.append("")
      report.append("Errors:")
      for e in errors {
        report.append("  [ERR] \(shortName(for: e.category)): \(e.error)")
      }
    }

    report.append("")
    report.append("Screenshots saved to /tmp/xcforge-a11y-*")

    let failed = results.filter { !$0.passed && !$0.isBase }
    if !failed.isEmpty {
      report.append("")
      report.append("Layout issues detected at larger sizes — check for truncation or overlap.")
    }

    var content: [Tool.Content] = [
      .text(text: report.joined(separator: "\n"), annotations: nil, _meta: nil)
    ]

    // Include inline screenshots for failed sizes
    for r in results where !r.passed && !r.isBase {
      if let img = VisualTools.loadCGImage(path: r.screenshotPath),
        let data = try? FramebufferCapture.encodeImage(img, format: "jpeg", quality: 0.7)
      {
        content.append(
          .image(
            data: data.base64EncodedString(), mimeType: "image/jpeg",
            annotations: nil, _meta: nil
          ))
        content.append(
          .text(
            text: "\(r.shortName) — diff \(String(format: "%.2f%%", r.diffPercent))",
            annotations: nil, _meta: nil
          ))
      }
    }

    return .init(content: content, isError: allPassed ? nil : true)
  }

  private static func buildLocalizationReport(
    results: [LocaleCheckResult], errors: [(locale: String, error: String)],
    threshold: Double, elapsed: String, allPassed: Bool
  ) -> CallTool.Result {
    let status = allPassed ? "PASS" : "FAIL"
    var report: [String] = []
    report.append("[\(status)] Localization Layout Check (\(elapsed)s)")
    report.append("Threshold: \(String(format: "%.1f", threshold))%")
    report.append("Locales tested: \(results.count)")
    report.append("")

    for r in results {
      let icon: String
      if r.isBase {
        icon = "[BASE]"
      } else {
        icon = r.passed ? "[OK]" : "[FAIL]"
      }
      let diffStr = r.isBase ? "—" : String(format: "%.2f%%", r.diffPercent)
      let rtlTag = r.isRTL ? " [RTL]" : ""
      report.append("  \(icon) \(r.locale)\(rtlTag) (\(r.width)x\(r.height)) diff: \(diffStr)")
      if let dp = r.diffPath {
        report.append("       Diff: \(dp)")
      }
    }

    if !errors.isEmpty {
      report.append("")
      report.append("Errors:")
      for e in errors {
        report.append("  [ERR] \(e.locale): \(e.error)")
      }
    }

    report.append("")
    report.append("Screenshots saved to /tmp/xcforge-l10n-*")

    let rtlFailed = results.filter { !$0.passed && $0.isRTL }
    if !rtlFailed.isEmpty {
      report.append("")
      report.append("RTL layout issues detected — check for mirroring and text alignment.")
    }

    var content: [Tool.Content] = [
      .text(text: report.joined(separator: "\n"), annotations: nil, _meta: nil)
    ]

    // Include inline screenshots for failed locales
    for r in results where !r.passed && !r.isBase {
      if let img = VisualTools.loadCGImage(path: r.screenshotPath),
        let data = try? FramebufferCapture.encodeImage(img, format: "jpeg", quality: 0.7)
      {
        content.append(
          .image(
            data: data.base64EncodedString(), mimeType: "image/jpeg",
            annotations: nil, _meta: nil
          ))
        content.append(
          .text(
            text:
              "\(r.locale)\(r.isRTL ? " [RTL]" : "") — diff \(String(format: "%.2f%%", r.diffPercent))",
            annotations: nil, _meta: nil
          ))
      }
    }

    return .init(content: content, isError: allPassed ? nil : true)
  }
}

extension AccessibilityTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "accessibility_check": return await accessibilityCheck(args, env: env)
    case "localization_check": return await localizationCheck(args, env: env)
    default: return nil
    }
  }
}
