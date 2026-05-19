import Foundation
import MCP

/// `pose` is a sugar tool that composes `build → install → launch` and forwards
/// a launch-arg key/value pair so apps with a debug-router that reads
/// `ProcessInfo.arguments` can deep-link into a specific screen on every
/// iteration. The launch-arg key defaults to `-pose` but is configurable per call.
public enum PoseTools {
  public static let group = "pose"

  public struct PoseExecution: Codable, Sendable {
    public let succeeded: Bool
    public let pose: String
    public let key: String
    public let bundleId: String?
    public let appPath: String?
    public let scheme: String
    public let simulator: String
    public let launchMessage: String
    public let screenshotPath: String?
    public let screenshotWarning: String?
    public let elapsed: String
  }

  public static let tools: [Tool] = [
    Tool(
      name: "pose",
      description: """
        Sugar over `build_run_sim` that appends a `<key> <name>` pair to the app's launch \
        arguments — designed for apps with a debug-router that reads ProcessInfo.arguments \
        to deep-link into a screen. Composes existing build + install + launch, optionally \
        captures a post-launch screenshot. Default key is `-pose`; override via `key`.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "name": .object([
            "type": .string("string"),
            "description": .string("Pose name to pass after `key` (e.g. 'Settings')."),
          ]),
          "key": .object([
            "type": .string("string"),
            "description": .string(
              "Launch-arg key. Default: -pose"),
          ]),
          "project": .object([
            "type": .string("string"),
            "description": .string(
              "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."
            ),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Xcode scheme name. Auto-detected if omitted."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration (Debug/Release). Default: Debug"),
          ]),
          "screenshot": .object([
            "type": .string("string"),
            "description": .string(
              "Optional output path. After a successful launch, capture a PNG to this path. Failures here only warn."
            ),
          ]),
          "screenshotDelay": .object([
            "type": .string("number"),
            "description": .string(
              "Ceiling (seconds) for the post-launch wait before screenshot. Polls WDA for active CFBundleIdentifier and proceeds as soon as the app is foreground; falls back to sleeping the residual budget if WDA is unreachable. Default 2.5. Pass 0 to capture immediately."
            ),
          ]),
          "waitFor": .object([
            "type": .string("string"),
            "description": .string(
              "Readiness signal(s), comma-separated (all must hold): `launch-complete`, `a11y:<id>`, `text:<substring>`. When set, replaces the screenshotDelay poll/sleep with a real element-presence gate (AXP-first, WDA fallback). Warn-only — never fails the pose."
            ),
          ]),
          "timeout": .object([
            "type": .string("number"),
            "description": .string(
              "Ceiling in seconds for `waitFor`. Capture happens the instant the signal holds, so a high ceiling costs nothing on the fast path. Default 20."
            ),
          ]),
        ]),
        "required": .array([.string("name")]),
      ])
    )
  ]

  // MARK: - Input

  struct PoseInput: Decodable {
    let name: String
    let key: String?
    let project: String?
    let scheme: String?
    let simulator: String?
    let configuration: String?
    let screenshot: String?
    let screenshotDelay: Double?
    let waitFor: String?
    let timeout: Double?
  }

  // MARK: - Execution

  public static func executePose(
    name: String,
    key: String = "-pose",
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    configuration: String = "Debug",
    screenshotPath: String? = nil,
    screenshotDelay: Double = 2.5,
    waitFor: String? = nil,
    waitTimeout: Double? = nil,
    env: Environment = .live
  ) async -> PoseExecution {
    let start = CFAbsoluteTimeGetCurrent()

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      return PoseExecution(
        succeeded: false,
        pose: name,
        key: key,
        bundleId: nil,
        appPath: nil,
        scheme: scheme ?? "?",
        simulator: simulator ?? "?",
        launchMessage: "Pose name is empty — provide a non-empty screen identifier",
        screenshotPath: nil,
        screenshotWarning: nil,
        elapsed: "0.0"
      )
    }

    let buildExec: BuildTools.BuildExecution
    do {
      buildExec = try await BuildTools.executeBuild(
        project: project,
        scheme: scheme,
        simulator: simulator,
        configuration: configuration,
        env: env
      )
    } catch {
      let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
      return PoseExecution(
        succeeded: false,
        pose: name,
        key: key,
        bundleId: nil,
        appPath: nil,
        scheme: scheme ?? "?",
        simulator: simulator ?? "?",
        launchMessage: "Build error: \(error)",
        screenshotPath: nil,
        screenshotWarning: nil,
        elapsed: elapsed
      )
    }

    guard buildExec.succeeded, let appPath = buildExec.appPath, let bundleId = buildExec.bundleId
    else {
      let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
      return PoseExecution(
        succeeded: false,
        pose: name,
        key: key,
        bundleId: buildExec.bundleId,
        appPath: buildExec.appPath,
        scheme: buildExec.scheme,
        simulator: buildExec.simulator,
        launchMessage: BuildTools.formatBuildFailure(buildExec),
        screenshotPath: nil,
        screenshotWarning: nil,
        elapsed: elapsed
      )
    }

    let resolvedSim = buildExec.simulator
    let bootResult = await SimTools.executeBootSim(simulator: resolvedSim, env: env)
    if !bootResult.succeeded {
      let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
      return PoseExecution(
        succeeded: false,
        pose: name,
        key: key,
        bundleId: bundleId,
        appPath: appPath,
        scheme: buildExec.scheme,
        simulator: resolvedSim,
        launchMessage: "Boot failed: \(bootResult.message)",
        screenshotPath: nil,
        screenshotWarning: nil,
        elapsed: elapsed
      )
    }

    let installResult = await SimTools.executeInstallApp(
      simulator: resolvedSim, appPath: appPath, env: env)
    if !installResult.succeeded {
      let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
      return PoseExecution(
        succeeded: false,
        pose: name,
        key: key,
        bundleId: bundleId,
        appPath: appPath,
        scheme: buildExec.scheme,
        simulator: resolvedSim,
        launchMessage: "Install failed: \(installResult.message)",
        screenshotPath: nil,
        screenshotWarning: nil,
        elapsed: elapsed
      )
    }

    let launchResult = await SimTools.executeLaunchApp(
      simulator: resolvedSim, bundleId: bundleId, args: [key, trimmedName], env: env)
    if !launchResult.succeeded {
      let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
      return PoseExecution(
        succeeded: false,
        pose: name,
        key: key,
        bundleId: bundleId,
        appPath: appPath,
        scheme: buildExec.scheme,
        simulator: resolvedSim,
        launchMessage: "Launch failed: \(launchResult.message)",
        screenshotPath: nil,
        screenshotWarning: nil,
        elapsed: elapsed
      )
    }

    // Tell WDAClient which app we just launched. Without this hint, any subsequent
    // implicit `ensureSession()` (e.g. from `ui ls --source wda`) creates a session with
    // no bundleId capability and silently activates Springboard.
    await env.wdaClient.recordLaunchedApp(bundleId: bundleId)

    // Optional screenshot — failures here only warn; do not fail the pose.
    var screenshotResultPath: String?
    var screenshotWarning: String?
    if let path = screenshotPath {
      // New explicit gate (raises the ceiling only via an explicit flag — the
      // default path below is unchanged for callers passing no new flags).
      // Readiness failure is warn-only: it NEVER hard-fails the pose, it
      // degrades and reports the mode in the warning line.
      if let waitFor, !waitFor.trimmingCharacters(in: .whitespaces).isEmpty {
        let timeout = waitTimeout ?? 20
        let parsed = ReadinessProbe.Signal.parseSpec(waitFor)
        let probe = await ReadinessProbe.waitReady(
          signals: parsed.signals,
          timeout: timeout,
          specWasUnparseable: parsed.allUnparseable,
          simulator: simulator,
          env: env
        )
        if !probe.ready {
          let why = probe.reason ?? "signal(s) not satisfied before timeout"
          screenshotWarning =
            "Readiness gate not satisfied (mode: \(probe.mode.rawValue), "
            + "\(probe.elapsedMs)ms): \(why) — capturing anyway"
        }
      } else {
        // Legacy path — unchanged. Wait for the app to actually become
        // foreground before capture. Sanitize: reject NaN/inf (would trap the
        // UInt64 cast) and clamp so a typo can't strand the process for hours.
        // Explicit 0 skips both poll and sleep.
        let delay: Double = {
          guard screenshotDelay.isFinite, screenshotDelay > 0 else { return 0 }
          return min(screenshotDelay, 60)
        }()
        if delay > 0 {
          let pollStart = CFAbsoluteTimeGetCurrent()
          let matched = await env.wdaClient.pollForActiveBundleId(
            target: bundleId, budget: delay)
          if !matched {
            let remaining = delay - (CFAbsoluteTimeGetCurrent() - pollStart)
            if remaining > 0 {
              try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
          }
        }
      }
      do {
        let udid = try await SimTools.resolveSimulator(resolvedSim, env: env)
        try await VisualTools.captureScreenshot(
          simulator: udid, format: "png", outputPath: path)
        screenshotResultPath = path
      } catch {
        screenshotWarning = "Screenshot capture failed: \(error)"
      }
    }

    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    return PoseExecution(
      succeeded: true,
      pose: name,
      key: key,
      bundleId: bundleId,
      appPath: appPath,
      scheme: buildExec.scheme,
      simulator: resolvedSim,
      launchMessage: launchResult.message,
      screenshotPath: screenshotResultPath,
      screenshotWarning: screenshotWarning,
      elapsed: elapsed
    )
  }

  // MARK: - MCP Dispatch

  static func pose(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(PoseInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let key = input.key ?? "-pose"
      let exec = await executePose(
        name: input.name,
        key: key,
        project: input.project,
        scheme: input.scheme,
        simulator: input.simulator,
        configuration: input.configuration ?? "Debug",
        screenshotPath: input.screenshot,
        screenshotDelay: input.screenshotDelay ?? 2.5,
        waitFor: input.waitFor,
        waitTimeout: input.timeout,
        env: env
      )

      var lines: [String] = []
      if exec.succeeded {
        lines.append("Posed '\(exec.pose)' in \(exec.elapsed)s")
      } else {
        lines.append("Pose '\(exec.pose)' FAILED in \(exec.elapsed)s")
      }
      lines.append("Key: \(exec.key)")
      lines.append("Scheme: \(exec.scheme)")
      lines.append("Simulator: \(exec.simulator)")
      if let bid = exec.bundleId { lines.append("Bundle ID: \(bid)") }
      if let path = exec.appPath { lines.append("App path: \(path)") }
      lines.append("Launch: \(exec.launchMessage)")
      if let path = exec.screenshotPath { lines.append("Screenshot: \(path)") }
      if let warning = exec.screenshotWarning { lines.append("Warning: \(warning)") }

      let body = lines.joined(separator: "\n")
      return exec.succeeded ? .ok(body) : .fail(body)
    }
  }
}

extension PoseTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "pose": return await pose(args, env: env)
    default: return nil
    }
  }
}
