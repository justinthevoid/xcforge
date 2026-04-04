import Foundation
import MCP

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
            description: "Take a screenshot of a booted simulator. Returns the image inline. 3-tier: burst (~10ms, native) → stream (~20ms, ScreenCaptureKit) → safe (~320ms, simctl). Simulator is auto-detected if omitted.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string("Simulator name or UDID. Auto-detected from booted simulator if omitted."),
                    ]),
                    "format": .object([
                        "type": .string("string"),
                        "description": .string("Image format: png or jpeg. Default: jpeg"),
                    ]),
                ]),
            ])
        ),
    ]

    // MARK: - Input Types

    struct ScreenshotInput: Decodable {
        let simulator: String?
        let format: String?
    }

    static func screenshot(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(ScreenshotInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input): return await screenshotImpl(input, env: env)
        }
    }

    private static func screenshotImpl(_ input: ScreenshotInput, env: Environment) async -> CallTool.Result {
        let sim: String
        do {
            sim = try await env.session.resolveSimulator(input.simulator)
        } catch {
            return .fail("\(error)")
        }
        let format = input.format ?? "jpeg"

        let start = CFAbsoluteTimeGetCurrent()

        // Fast path: inline capture (macOS 14+)
        if #available(macOS 14.0, *) {
            do {
                let result = try await FramebufferCapture.captureInline(
                    simulator: sim, format: format
                )
                let elapsed = String(
                    format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                let mimeType = format.hasPrefix("jp") ? "image/jpeg" : "image/png"
                return .init(content: [
                    .image(
                        data: result.base64, mimeType: mimeType, annotations: nil, _meta: nil),
                    .text(
                        text: "\(result.width)x\(result.height) | \(result.dataSize / 1024)KB | \(elapsed)ms (\(result.method))",
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
        let outputPath = "/tmp/ss-screenshot.\(format)"
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
                    return .init(content: [
                        .image(
                            data: data.base64EncodedString(), mimeType: mimeType,
                            annotations: nil, _meta: nil),
                        .text(
                            text: "\(data.count / 1024)KB | \(elapsed)ms (simctl)",
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
                        detail: "xcforge captured a screenshot frame but could not decode the encoded image data."
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

            let message = bestFailureDetail(stdout: result.stdout, stderr: result.stderr, priorError: priorError)
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

    private static func bestFailureDetail(stdout: String?, stderr: String?, priorError: Error?) -> String {
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
}

extension ScreenshotTools: ToolProvider {
    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
        switch name {
        case "screenshot": return await screenshot(args, env: env)
        default: return nil
        }
    }
}
