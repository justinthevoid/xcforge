import CoreGraphics
import Foundation
import ImageIO
import MCP

public enum VisualTools {
    private static let defaultBaselineDir = "visual-baselines"

    public static let tools: [Tool] = [
        Tool(
            name: "save_visual_baseline",
            description: "Take a screenshot and save it as a named baseline for later visual comparison.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": .string("string"), "description": .string("Baseline name (e.g. 'login-screen'). Used as filename.")]),
                    "simulator": .object(["type": .string("string"), "description": .string("Simulator name or UDID. Auto-detected from booted simulator if omitted.")]),
                    "baseline_dir": .object(["type": .string("string"), "description": .string("Directory to store baselines. Default: visual-baselines/")]),
                ]),
                "required": .array([.string("name")]),
            ])
        ),
        Tool(
            name: "compare_visual",
            description: "Take a screenshot and compare it pixel-by-pixel against a saved baseline. Returns diff percentage and a diff image path.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": .string("string"), "description": .string("Baseline name to compare against.")]),
                    "simulator": .object(["type": .string("string"), "description": .string("Simulator name or UDID. Auto-detected from booted simulator if omitted.")]),
                    "threshold": .object(["type": .string("number"), "description": .string("Max allowed diff percentage (0-100). Default: 0.5")]),
                    "baseline_dir": .object(["type": .string("string"), "description": .string("Directory where baselines are stored. Default: visual-baselines/")]),
                ]),
                "required": .array([.string("name")]),
            ])
        ),
    ]

    // MARK: - Input Types

    struct SaveBaselineInput: Decodable {
        let name: String
        let simulator: String?
        let baseline_dir: String?
    }

    struct CompareInput: Decodable {
        let name: String
        let simulator: String?
        let threshold: Double?
        let baseline_dir: String?
    }

    // MARK: - Save Baseline

    static func saveVisualBaseline(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(SaveBaselineInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            guard !input.name.isEmpty else { return .fail("Missing required: name") }
            return await saveVisualBaselineImpl(input, env: env)
        }
    }

    private static func saveVisualBaselineImpl(_ input: SaveBaselineInput, env: Environment) async -> CallTool.Result {
        let sim: String
        do {
            sim = try await env.session.resolveSimulator(input.simulator)
        } catch {
            return .fail("\(error)")
        }
        let baselineDir = input.baseline_dir ?? defaultBaselineDir

        do {
            // Ensure baseline directory exists
            try FileManager.default.createDirectory(atPath: baselineDir, withIntermediateDirectories: true)

            let baselinePath = "\(baselineDir)/\(sanitize(input.name)).png"

            // Capture screenshot — burst (CoreSimulator) or simctl fallback
            let cgImage: CGImage
            if CoreSimCapture.isAvailable {
                do {
                    cgImage = try await CoreSimCapture.captureImageAsync(simulator: sim)
                } catch {
                    Log.warn("saveBaseline: CoreSimCapture failed, falling back to simctl: \(error)")
                    cgImage = try await simctlCapture(sim: sim, tmpPrefix: "baseline", env: env)
                }
            } else {
                cgImage = try await simctlCapture(sim: sim, tmpPrefix: "baseline", env: env)
            }

            // Save as PNG baseline
            let fm = FileManager.default
            if fm.fileExists(atPath: baselinePath) {
                try fm.removeItem(atPath: baselinePath)
            }
            savePNG(image: cgImage, path: baselinePath)

            let fileSize = (try? fm.attributesOfItem(atPath: baselinePath)[.size] as? Int) ?? 0
            return .ok("Baseline saved: \(baselinePath)\nSize: \(fileSize / 1024)KB")
        } catch {
            return .fail("Save baseline failed: \(error)")
        }
    }

    // MARK: - Compare Visual

    static func compareVisual(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(CompareInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            guard !input.name.isEmpty else { return .fail("Missing required: name") }
            return await compareVisualImpl(input, env: env)
        }
    }

    private static func compareVisualImpl(_ input: CompareInput, env: Environment) async -> CallTool.Result {
        let sim: String
        do {
            sim = try await env.session.resolveSimulator(input.simulator)
        } catch {
            return .fail("\(error)")
        }
        let threshold = input.threshold ?? 0.5
        let baselineDir = input.baseline_dir ?? defaultBaselineDir

        let runId = UUID().uuidString.prefix(8)
        let baselinePath = "\(baselineDir)/\(sanitize(input.name)).png"
        let currentPath = "/tmp/ss-visual-current-\(runId).png"
        let diffPath = "/tmp/ss-visual-diff-\(sanitize(input.name))-\(runId).png"

        // Check baseline exists
        guard FileManager.default.fileExists(atPath: baselinePath) else {
            return .fail("Baseline not found: \(baselinePath)\nRun save_visual_baseline first.")
        }

        do {
            // Capture current screenshot — burst or simctl fallback
            let currentImage: CGImage
            if CoreSimCapture.isAvailable {
                do {
                    currentImage = try await CoreSimCapture.captureImageAsync(simulator: sim)
                } catch {
                    Log.warn("compareVisual: CoreSimCapture failed, falling back to simctl: \(error)")
                    currentImage = try await simctlCapture(sim: sim, tmpPrefix: "compare", env: env)
                }
            } else {
                currentImage = try await simctlCapture(sim: sim, tmpPrefix: "compare", env: env)
            }

            // Load baseline
            guard let baselineImage = loadCGImage(path: baselinePath) else {
                return .fail("Failed to load baseline image: \(baselinePath)")
            }

            // Compare
            let comparison = pixelCompare(baseline: baselineImage, current: currentImage)

            // Save diff image
            if let diffImage = comparison.diffImage {
                savePNG(image: diffImage, path: diffPath)
            }

            let passed = comparison.diffPercent <= threshold
            let status = passed ? "PASS" : "FAIL"
            let emoji = passed ? "" : " ⚠️"

            var lines = [
                "[\(status)] Visual comparison: \(input.name)\(emoji)",
                "Diff: \(String(format: "%.2f", comparison.diffPercent))% (threshold: \(String(format: "%.1f", threshold))%)",
                "Changed pixels: \(comparison.changedPixels) / \(comparison.totalPixels)",
            ]

            if comparison.sizeMismatch {
                lines.append("WARNING: Size mismatch — baseline: \(baselineImage.width)x\(baselineImage.height), current: \(currentImage.width)x\(currentImage.height)")
            }

            lines.append("Baseline: \(baselinePath)")
            lines.append("Current:  \(currentPath)")
            if comparison.diffImage != nil {
                lines.append("Diff:     \(diffPath)")
            }

            if passed {
                return .ok(lines.joined(separator: "\n"))
            } else {
                return .fail(lines.joined(separator: "\n"))
            }
        } catch {
            return .fail("Compare failed: \(error)")
        }
    }

    // MARK: - CLI Screenshot Capture

    /// Capture a screenshot to the given path using the best available method.
    /// Tries CoreSimCapture (fast, ~15ms) with simctl fallback (~320ms). Public for CLI use.
    public static func captureScreenshot(
        simulator: String,
        format: String,
        outputPath: String
    ) async throws {
        // Ensure parent directory exists
        let parentDir = (outputPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Fast path: CoreSimCapture → encode → write file
        if CoreSimCapture.isAvailable {
            do {
                let cgImage = try await CoreSimCapture.captureImageAsync(simulator: simulator)
                try FramebufferCapture.saveImage(cgImage, format: format, quality: 0.9, path: outputPath)
                return
            } catch {
                Log.warn("CoreSimCapture file capture failed, falling back to simctl: \(error)")
            }
        }

        // Fallback: simctl io screenshot
        let result = try await Shell.xcrun(
            timeout: 15, "simctl", "io", simulator, "screenshot",
            "--type=\(format)", outputPath
        )
        guard result.succeeded else {
            throw NSError(
                domain: "VisualTools", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Screenshot failed: \(result.stderr)"]
            )
        }
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw NSError(
                domain: "VisualTools", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Screenshot file not found at \(outputPath)"]
            )
        }
    }

    /// Capture a CGImage from the simulator using the best available method. Public for CLI use.
    public static func captureCGImage(simulator: String, env: Environment = .live) async throws -> CGImage {
        if CoreSimCapture.isAvailable {
            do {
                return try await CoreSimCapture.captureImageAsync(simulator: simulator)
            } catch {
                Log.warn("CoreSimCapture failed, falling back to simctl: \(error)")
                return try await simctlCapture(sim: simulator, tmpPrefix: "cli", env: env)
            }
        }
        return try await simctlCapture(sim: simulator, tmpPrefix: "cli", env: env)
    }

    // MARK: - simctl Screenshot Fallback

    private static func simctlCapture(sim: String, tmpPrefix: String, env: Environment) async throws -> CGImage {
        let tmpPath = "/tmp/ss-\(tmpPrefix)-\(UUID().uuidString).png"
        let result = try await env.shell.xcrun(
            timeout: 10, "simctl", "io", sim, "screenshot", "--type=png", tmpPath)
        guard result.succeeded else {
            throw NSError(domain: "VisualTools", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Screenshot failed: \(result.stderr)"])
        }
        guard let loaded = loadCGImage(path: tmpPath) else {
            throw NSError(domain: "VisualTools", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load screenshot from \(tmpPath)"])
        }
        return loaded
    }

    // MARK: - Image Helpers (internal for reuse by MultiDeviceTools)

    public static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
    }

    public static func loadCGImage(path: String) -> CGImage? {
        guard let dataProvider = CGDataProvider(filename: path) else { return nil }
        return CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    public static func savePNG(image: CGImage, path: String) {
        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            "public.png" as CFString,
            1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    public struct ComparisonResult {
        public let diffPercent: Double
        public let changedPixels: Int
        public let totalPixels: Int
        public let sizeMismatch: Bool
        public let diffImage: CGImage?
    }

    public static func pixelCompare(baseline: CGImage, current: CGImage) -> ComparisonResult {
        let bw = baseline.width, bh = baseline.height
        let cw = current.width, ch = current.height
        let sizeMismatch = bw != cw || bh != ch

        // Use the smaller dimensions for pixel-by-pixel comparison
        let w = min(bw, cw)
        let h = min(bh, ch)
        // Total pixels = union of both images (larger area covers all pixels that could differ)
        let largerArea = max(bw * bh, cw * ch)
        let totalPixels = max(largerArea, w * h)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel

        // Render both images into raw RGBA buffers
        var baselinePixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        var currentPixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        var diffPixels = [UInt8](repeating: 0, count: h * bytesPerRow)

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let baseCtx = CGContext(data: &baselinePixels, width: w, height: h,
                                       bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                       space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
              let currCtx = CGContext(data: &currentPixels, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return ComparisonResult(diffPercent: 100, changedPixels: totalPixels,
                                    totalPixels: totalPixels, sizeMismatch: sizeMismatch, diffImage: nil)
        }

        baseCtx.draw(baseline, in: CGRect(x: 0, y: 0, width: w, height: h))
        currCtx.draw(current, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Compare pixel by pixel
        var changedPixels = 0
        let pixelThreshold: Int = 10 // per-channel tolerance for anti-aliasing

        for y in 0..<h {
            for x in 0..<w {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let dr = abs(Int(baselinePixels[offset]) - Int(currentPixels[offset]))
                let dg = abs(Int(baselinePixels[offset + 1]) - Int(currentPixels[offset + 1]))
                let db = abs(Int(baselinePixels[offset + 2]) - Int(currentPixels[offset + 2]))

                if dr > pixelThreshold || dg > pixelThreshold || db > pixelThreshold {
                    changedPixels += 1
                    // Red highlight in diff image
                    diffPixels[offset] = 255     // R
                    diffPixels[offset + 1] = 0   // G
                    diffPixels[offset + 2] = 0   // B
                    diffPixels[offset + 3] = 255 // A
                } else {
                    // Dimmed original in diff image
                    diffPixels[offset] = currentPixels[offset] / 3
                    diffPixels[offset + 1] = currentPixels[offset + 1] / 3
                    diffPixels[offset + 2] = currentPixels[offset + 2] / 3
                    diffPixels[offset + 3] = 255
                }
            }
        }

        // Add changed pixels from size mismatch area
        if sizeMismatch {
            changedPixels += totalPixels - (w * h)
        }

        let diffPercent = totalPixels > 0 ? Double(changedPixels) / Double(totalPixels) * 100.0 : 0.0

        // Create diff image
        let diffImage: CGImage? = {
            guard let provider = CGDataProvider(data: Data(diffPixels) as CFData) else { return nil }
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo,
                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }()

        return ComparisonResult(diffPercent: diffPercent, changedPixels: changedPixels,
                                totalPixels: totalPixels, sizeMismatch: sizeMismatch, diffImage: diffImage)
    }
}

extension VisualTools: ToolProvider {
    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
        switch name {
        case "save_visual_baseline": return await saveVisualBaseline(args, env: env)
        case "compare_visual":       return await compareVisual(args, env: env)
        default: return nil
        }
    }
}
