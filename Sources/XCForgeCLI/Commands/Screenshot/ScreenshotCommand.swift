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

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() async throws {
        let output = self.output ?? "/tmp/xcforge-screenshot.\(format)"

        let env = Environment.live
        let sim = try await env.session.resolveSimulator(simulator)

        try await VisualTools.captureScreenshot(
            simulator: sim,
            format: format,
            outputPath: output
        )

        let attrs = try FileManager.default.attributesOfItem(atPath: output)
        let fileSize = (attrs[.size] as? Int) ?? 0
        let sizeKB = fileSize / 1024

        let result = ScreenshotResult(
            succeeded: true,
            path: output,
            format: format,
            sizeKB: sizeKB
        )

        if json {
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

        if json {
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

        if json {
            print(try WorkflowJSONRenderer.renderJSON(result))
        } else {
            print(ScreenshotRenderer.renderCompare(result, name: name))
        }

        if !passed {
            throw ExitCode.failure
        }
    }
}
