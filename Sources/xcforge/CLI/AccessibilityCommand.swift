import ArgumentParser
import CoreGraphics
import Foundation
import xcforgeCore

struct Accessibility: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accessibility",
        abstract: "Check Dynamic Type and localization layout compliance.",
        subcommands: [AccessibilityDynamicType.self, AccessibilityLocalization.self],
        defaultSubcommand: AccessibilityDynamicType.self
    )
}

// MARK: - Codable Result Types

struct DynamicTypeResult: Codable {
    let passed: Bool
    let sizesChecked: Int
    let failures: Int
    let threshold: Double
    let elapsed: String
    let sizes: [SizeEntry]
    let errors: [ErrorEntry]

    struct SizeEntry: Codable {
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

    struct ErrorEntry: Codable {
        let category: String
        let error: String
    }
}

struct LocalizationResult: Codable {
    let passed: Bool
    let localesChecked: Int
    let failures: Int
    let threshold: Double
    let elapsed: String
    let locales: [LocaleEntry]
    let errors: [ErrorEntry]

    struct LocaleEntry: Codable {
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

    struct ErrorEntry: Codable {
        let locale: String
        let error: String
    }
}

// MARK: - Dynamic Type Check

struct AccessibilityDynamicType: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dynamic-type",
        abstract: "Check the current screen across Dynamic Type content size categories."
    )

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Option(
        help:
            "Comma-separated content size categories. Use 'all' for all 12. Default: XS,L,XXXL,AccessibilityXXXL"
    )
    var sizes: String?

    @Option(help: "Max allowed diff % between base and each size. Default: 5.0")
    var threshold: Double = 5.0

    @Option(help: "Seconds to wait after setting size before screenshot. Default: 1.5")
    var settleTime: Double = 1.5

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let sizes = self.sizes
        let threshold = self.threshold
        let settleTime = self.settleTime
        let json = self.json

        try runAsync {
            let env = Environment.live
            let sim = try await env.session.resolveSimulator(simulator)

            // Parse size categories
            let categories: [String]
            if let s = sizes, !s.isEmpty {
                if s.lowercased() == "all" {
                    categories = AccessibilityTools.allSizeCategories
                } else {
                    categories = s.split(separator: ",").map { raw in
                        let trimmed = raw.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("UICTContentSizeCategory") {
                            return trimmed
                        }
                        return "UICTContentSizeCategory\(trimmed)"
                    }
                }
            } else {
                categories = AccessibilityTools.defaultSizeCategories
            }

            guard categories.count >= 2 else {
                throw ValidationError("Need at least 2 size categories to compare.")
            }

            let start = CFAbsoluteTimeGetCurrent()
            let runId = String(UUID().uuidString.prefix(8))

            var sizeEntries: [DynamicTypeResult.SizeEntry] = []
            var errorEntries: [DynamicTypeResult.ErrorEntry] = []
            var capturedImages: [(String, CGImage)] = []

            // Screenshot each size
            for category in categories {
                do {
                    try await AccessibilityTools.setContentSize(category, simulator: sim)
                } catch {
                    errorEntries.append(.init(category: category, error: "\(error)"))
                    continue
                }

                try? await Task.sleep(nanoseconds: UInt64(settleTime * 1_000_000_000))

                let path = "/tmp/xcforge-a11y-\(runId)-\(VisualTools.sanitize(category)).png"
                do {
                    let img = try await VisualTools.captureCGImage(simulator: sim)
                    VisualTools.savePNG(image: img, path: path)
                    capturedImages.append((category, img))

                    // Compare against first captured
                    if capturedImages.count == 1 {
                        sizeEntries.append(.init(
                            category: category,
                            shortName: AccessibilityTools.shortName(for: category),
                            width: img.width, height: img.height,
                            diffPercent: 0, passed: true, isBase: true,
                            screenshotPath: path, diffPath: nil
                        ))
                    } else {
                        let base = capturedImages[0].1
                        let cmp = VisualTools.pixelCompare(baseline: base, current: img)
                        let passed = cmp.diffPercent <= threshold
                        var diffPath: String?
                        if let diffImg = cmp.diffImage, !passed {
                            let dp =
                                "/tmp/xcforge-a11y-diff-\(runId)-\(VisualTools.sanitize(category)).png"
                            VisualTools.savePNG(image: diffImg, path: dp)
                            diffPath = dp
                        }
                        sizeEntries.append(.init(
                            category: category,
                            shortName: AccessibilityTools.shortName(for: category),
                            width: img.width, height: img.height,
                            diffPercent: cmp.diffPercent, passed: passed, isBase: false,
                            screenshotPath: path, diffPath: diffPath
                        ))
                    }
                } catch {
                    errorEntries.append(.init(category: category, error: "Screenshot: \(error)"))
                }
            }

            // Restore default size
            _ = try? await AccessibilityTools.setContentSize(
                "UICTContentSizeCategoryL", simulator: sim
            )

            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            let failures = sizeEntries.filter { !$0.passed && !$0.isBase }.count
            let allPassed = failures == 0

            let result = DynamicTypeResult(
                passed: allPassed,
                sizesChecked: sizeEntries.count,
                failures: failures,
                threshold: threshold,
                elapsed: elapsed,
                sizes: sizeEntries,
                errors: errorEntries
            )

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(AccessibilityRenderer.renderDynamicType(result))
            }

            if !allPassed {
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Localization Check

struct AccessibilityLocalization: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "localization",
        abstract: "Check the current screen across locales including RTL languages."
    )

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Option(help: "App bundle identifier. Auto-detected from last build if omitted.")
    var bundleId: String?

    @Option(help: "Comma-separated locale identifiers. Use 'all' for 10 common locales. Default: en,de,ja,ar,he")
    var locales: String?

    @Option(help: "Max allowed diff % between base and each locale. Default: 10.0")
    var threshold: Double = 10.0

    @Option(help: "Seconds to wait after relaunching with new locale. Default: 3.0")
    var settleTime: Double = 3.0

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let bundleIdOpt = self.bundleId
        let locales = self.locales
        let threshold = self.threshold
        let settleTime = self.settleTime
        let json = self.json

        try runAsync {
            let env = Environment.live
            let sim = try await env.session.resolveSimulator(simulator)

            let bid: String
            if let b = bundleIdOpt, !b.isEmpty {
                bid = b
            } else if let cached = await env.session.bundleId {
                bid = cached
            } else {
                throw ValidationError(
                    "No bundle-id provided and none cached from a previous build."
                )
            }

            let localeList: [String]
            if let l = locales, !l.isEmpty {
                if l.lowercased() == "all" {
                    localeList = AccessibilityTools.allLocales
                } else {
                    localeList = l.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                }
            } else {
                localeList = AccessibilityTools.defaultLocales
            }

            guard localeList.count >= 2 else {
                throw ValidationError("Need at least 2 locales to compare.")
            }

            let start = CFAbsoluteTimeGetCurrent()
            let runId = String(UUID().uuidString.prefix(8))

            var localeEntries: [LocalizationResult.LocaleEntry] = []
            var errorEntries: [LocalizationResult.ErrorEntry] = []
            var capturedImages: [(String, CGImage)] = []

            for locale in localeList {
                let langCode =
                    locale.split(separator: "-").first.map(String.init) ?? locale
                let isRTL = AccessibilityTools.rtlLocales.contains(langCode)

                do {
                    try await AccessibilityTools.relaunchWithLocale(
                        locale, bundleId: bid, simulator: sim, isRTL: isRTL
                    )
                } catch {
                    errorEntries.append(.init(locale: locale, error: "\(error)"))
                    continue
                }

                try? await Task.sleep(nanoseconds: UInt64(settleTime * 1_000_000_000))

                let path = "/tmp/xcforge-l10n-\(runId)-\(VisualTools.sanitize(locale)).png"
                do {
                    let img = try await VisualTools.captureCGImage(simulator: sim)
                    VisualTools.savePNG(image: img, path: path)
                    capturedImages.append((locale, img))

                    if capturedImages.count == 1 {
                        localeEntries.append(.init(
                            locale: locale, isRTL: isRTL,
                            width: img.width, height: img.height,
                            diffPercent: 0, passed: true, isBase: true,
                            screenshotPath: path, diffPath: nil
                        ))
                    } else {
                        let base = capturedImages[0].1
                        let cmp = VisualTools.pixelCompare(baseline: base, current: img)
                        let passed = cmp.diffPercent <= threshold
                        var diffPath: String?
                        if let diffImg = cmp.diffImage, !passed {
                            let dp =
                                "/tmp/xcforge-l10n-diff-\(runId)-\(VisualTools.sanitize(locale)).png"
                            VisualTools.savePNG(image: diffImg, path: dp)
                            diffPath = dp
                        }
                        localeEntries.append(.init(
                            locale: locale, isRTL: isRTL,
                            width: img.width, height: img.height,
                            diffPercent: cmp.diffPercent, passed: passed, isBase: false,
                            screenshotPath: path, diffPath: diffPath
                        ))
                    }
                } catch {
                    errorEntries.append(.init(locale: locale, error: "Screenshot: \(error)"))
                }
            }

            // Restore base locale
            let baseLang =
                localeList[0].split(separator: "-").first.map(String.init) ?? localeList[0]
            let baseIsRTL = AccessibilityTools.rtlLocales.contains(baseLang)
            _ = try? await AccessibilityTools.relaunchWithLocale(
                localeList[0], bundleId: bid, simulator: sim, isRTL: baseIsRTL
            )

            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            let failures = localeEntries.filter { !$0.passed && !$0.isBase }.count
            let allPassed = failures == 0

            let result = LocalizationResult(
                passed: allPassed,
                localesChecked: localeEntries.count,
                failures: failures,
                threshold: threshold,
                elapsed: elapsed,
                locales: localeEntries,
                errors: errorEntries
            )

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(AccessibilityRenderer.renderLocalization(result))
            }

            if !allPassed {
                throw ExitCode.failure
            }
        }
    }
}
