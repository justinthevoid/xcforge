import Foundation

/// Executes a sequence of PlanSteps against WDA, collecting results.
public final class PlanExecutor: Sendable {
  public let errorStrategy: ErrorStrategy
  public let timeoutSeconds: Double
  private let session: SessionState
  private let wdaClient: WDAClient
  private let variables: VariableStore
  // nonisolated(unsafe) because PlanExecutor runs steps sequentially
  nonisolated(unsafe) private var results: [StepResult] = []
  nonisolated(unsafe) private var startTime: CFAbsoluteTime = 0

  public init(
    session: SessionState, wdaClient: WDAClient,
    errorStrategy: ErrorStrategy = .abortWithScreenshot, timeoutSeconds: Double = 120
  ) {
    self.session = session
    self.wdaClient = wdaClient
    self.errorStrategy = errorStrategy
    self.timeoutSeconds = timeoutSeconds
    self.variables = VariableStore()
  }

  /// Restore state from a suspended plan (for resume).
  public func restore(
    priorResults: [StepResult], savedBindings: [String: VariableStore.ElementBinding],
    startTime: CFAbsoluteTime
  ) {
    self.results = priorResults
    self.variables.restore(savedBindings)
    self.startTime = startTime
  }

  // MARK: - Execute

  public enum ExecuteResult: Sendable {
    case completed(PlanReport)
    case suspended(SuspendedPlan, partialReport: PlanReport)
  }

  public func execute(steps: [PlanStep], startAt: Int = 0) async -> ExecuteResult {
    if startTime == 0 { startTime = CFAbsoluteTimeGetCurrent() }

    for i in startAt..<steps.count {
      // Global timeout check
      let elapsed = CFAbsoluteTimeGetCurrent() - startTime
      if elapsed > timeoutSeconds {
        results.append(
          StepResult(
            index: i, type: "timeout", status: .failed,
            detail: "Plan timed out after \(Int(elapsed))s (limit: \(Int(timeoutSeconds))s)",
            durationMs: 0
          ))
        break
      }

      let stepStart = CFAbsoluteTimeGetCurrent()
      let step = steps[i]
      let typeName = stepTypeName(step)

      let outcome = await runStep(step, index: i)

      switch outcome {
      case .result(let status, let detail, let screenshot):
        let dur = Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000)
        results.append(
          StepResult(
            index: i, type: typeName, status: status,
            detail: detail, durationMs: dur, screenshotBase64: screenshot
          ))
        if status == .failed && errorStrategy != .continue {
          // Abort: capture diagnostic screenshot if strategy requires it
          if errorStrategy == .abortWithScreenshot {
            let ss = await captureScreenshot()
            if let last = results.last, last.screenshotBase64 == nil {
              results[results.count - 1] = StepResult(
                index: last.index, type: last.type, status: last.status,
                detail: last.detail, durationMs: last.durationMs,
                screenshotBase64: ss
              )
            }
          }
          return .completed(PlanReport(steps: results))
        }

      case .suspend(let question, let screenshot):
        let dur = Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000)
        results.append(
          StepResult(
            index: i, type: typeName, status: .suspended,
            detail: question, durationMs: dur, screenshotBase64: screenshot
          ))
        let suspended = SuspendedPlan(
          steps: steps,
          pauseIndex: i,
          question: question,
          completedResults: results,
          variableBindings: variables.exportAll(),
          errorStrategy: errorStrategy,
          timeoutSeconds: timeoutSeconds,
          startTime: startTime,
          screenshotBase64: screenshot
        )
        return .suspended(suspended, partialReport: PlanReport(steps: results))
      }
    }

    return .completed(PlanReport(steps: results))
  }

  // MARK: - Step Dispatch

  private enum StepOutcome: Sendable {
    case result(StepStatus, detail: String?, screenshot: String?)
    case suspend(question: String, screenshot: String?)
  }

  private func runStep(_ step: PlanStep, index: Int) async -> StepOutcome {
    do {
      switch step {
      case .navigate(let bundleId):
        _ = try await wdaClient.createSession(bundleId: bundleId)
        return .result(.passed, detail: "Navigated to \(bundleId)", screenshot: nil)

      case .navigateBack:
        // Press the back button via predicate
        let (eid, _) = try await wdaClient.findElement(
          using: "predicate string", value: "label == 'Back' OR identifier == 'Back'"
        )
        try await wdaClient.click(elementId: eid)
        return .result(.passed, detail: "Navigated back", screenshot: nil)

      case .find(let target, let using, let bindAs):
        let strategy = using ?? "predicate string"
        let searchValue: String
        if using == nil {
          let escaped = target.replacingOccurrences(of: "'", with: "\\'")
          searchValue = "label == '\(escaped)' OR identifier == '\(escaped)'"
        } else {
          searchValue = target
        }
        let (eid, _) = try await wdaClient.findElement(using: strategy, value: searchValue)
        if let name = bindAs {
          let cleanName = name.hasPrefix("$") ? String(name.dropFirst()) : name
          variables.bind(cleanName, VariableStore.ElementBinding(elementId: eid, label: target))
        }
        return .result(
          .passed, detail: "Found '\(target)'\(bindAs.map { " → \($0)" } ?? "")", screenshot: nil)

      case .findAll(let targets, let using):
        let strategy = using ?? "predicate string"
        var details: [String] = []
        for t in targets {
          let searchValue: String
          if using == nil {
            let escaped = t.label.replacingOccurrences(of: "'", with: "\\'")
            searchValue = "label == '\(escaped)' OR identifier == '\(escaped)'"
          } else {
            searchValue = t.label
          }
          let (eid, _) = try await wdaClient.findElement(using: strategy, value: searchValue)
          if let name = t.bindAs {
            let cleanName = name.hasPrefix("$") ? String(name.dropFirst()) : name
            variables.bind(cleanName, VariableStore.ElementBinding(elementId: eid, label: t.label))
          }
          details.append(t.label)
        }
        return .result(
          .passed, detail: "Found \(details.count) elements: \(details.joined(separator: ", "))",
          screenshot: nil)

      case .click(let target):
        let eid = try await variables.resolveTarget(target, wdaClient: wdaClient)

        // IndigoHID fast-path: resolve element rect, tap at center
        if IndigoHIDClient.isAvailable {
          do {
            let rect = try await wdaClient.getElementRect(elementId: eid)
            let cx = rect.x + rect.width / 2
            let cy = rect.y + rect.height / 2
            try await IndigoHIDClient.shared.tap(x: cx, y: cy)
            return .result(
              .passed, detail: "Clicked \(targetDescription(target)) (indigo)", screenshot: nil)
          } catch {
            Log.warn("IndigoHID click failed in plan, falling back to WDA: \(error)")
            await IndigoHIDClient.shared.invalidateCache()
          }
        }

        try await wdaClient.click(elementId: eid)
        return .result(.passed, detail: "Clicked \(targetDescription(target))", screenshot: nil)

      case .doubleTap(let target):
        let eid = try await variables.resolveTarget(target, wdaClient: wdaClient)
        let rect = try await wdaClient.getElementRect(elementId: eid)
        let cx = rect.x + rect.width / 2
        let cy = rect.y + rect.height / 2

        // IndigoHID fast-path
        if IndigoHIDClient.isAvailable {
          do {
            try await IndigoHIDClient.shared.doubleTap(x: cx, y: cy)
            return .result(
              .passed, detail: "Double-tapped \(targetDescription(target)) (indigo)",
              screenshot: nil)
          } catch {
            Log.warn("IndigoHID doubleTap failed in plan, falling back to WDA: \(error)")
            await IndigoHIDClient.shared.invalidateCache()
          }
        }

        try await wdaClient.doubleTap(x: cx, y: cy)
        return .result(
          .passed, detail: "Double-tapped \(targetDescription(target))", screenshot: nil)

      case .longPress(let target, let durationMs):
        let eid = try await variables.resolveTarget(target, wdaClient: wdaClient)
        let rect = try await wdaClient.getElementRect(elementId: eid)
        let cx = rect.x + rect.width / 2
        let cy = rect.y + rect.height / 2
        let dur = durationMs ?? 1000

        // IndigoHID fast-path
        if IndigoHIDClient.isAvailable {
          do {
            try await IndigoHIDClient.shared.longPress(x: cx, y: cy, durationMs: dur)
            return .result(
              .passed, detail: "Long-pressed \(targetDescription(target)) (indigo)", screenshot: nil
            )
          } catch {
            Log.warn("IndigoHID longPress failed in plan, falling back to WDA: \(error)")
            await IndigoHIDClient.shared.invalidateCache()
          }
        }

        try await wdaClient.longPress(x: cx, y: cy, durationMs: dur)
        return .result(
          .passed, detail: "Long-pressed \(targetDescription(target))", screenshot: nil)

      case .swipe(let direction, let target, let durationMs):
        let dur = durationMs ?? 300
        let size = try await wdaClient.getWindowSize()
        let (sx, sy, ex, ey) = swipeCoordinates(
          direction: direction, width: size.width, height: size.height)

        // IndigoHID fast-path for swipe
        if IndigoHIDClient.isAvailable {
          do {
            try await IndigoHIDClient.shared.swipe(
              startX: sx, startY: sy, endX: ex, endY: ey, durationMs: dur
            )
            _ = target
            return .result(.passed, detail: "Swiped \(direction) (indigo)", screenshot: nil)
          } catch {
            Log.warn("IndigoHID swipe failed in plan, falling back to WDA: \(error)")
            await IndigoHIDClient.shared.invalidateCache()
          }
        }

        try await wdaClient.swipe(startX: sx, startY: sy, endX: ex, endY: ey, durationMs: dur)
        _ = target
        return .result(.passed, detail: "Swiped \(direction)", screenshot: nil)

      case .typeText(let text, let target):
        if let t = target {
          let eid = try await variables.resolveTarget(t, wdaClient: wdaClient)
          try await wdaClient.setValue(elementId: eid, text: text)
        } else {
          // Type into currently focused element
          let (eid, _) = try await wdaClient.findElement(
            using: "class name", value: "XCUIElementTypeTextField"
          )
          try await wdaClient.setValue(elementId: eid, text: text)
        }
        return .result(
          .passed, detail: "Typed '\(text.prefix(20))\(text.count > 20 ? "..." : "")'",
          screenshot: nil)

      case .screenshot(let label):
        let ss = await captureScreenshot()
        let desc = label ?? "step-\(index)"
        return .result(.passed, detail: "Screenshot: \(desc)", screenshot: ss)

      case .wait(let seconds):
        let clamped = max(0, seconds)
        try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
        return .result(.passed, detail: "Waited \(seconds)s", screenshot: nil)

      case .waitFor(let text, let timeout, let condition):
        let maxWait = timeout ?? 10.0
        let deadline = CFAbsoluteTimeGetCurrent() + maxWait
        let escaped = text.replacingOccurrences(of: "'", with: "\\'")
        let predicate =
          "label == '\(escaped)' OR identifier == '\(escaped)' OR value == '\(escaped)'"
        var found = false

        while CFAbsoluteTimeGetCurrent() < deadline {
          do {
            _ = try await wdaClient.findElement(using: "predicate string", value: predicate)
            found = true
            break
          } catch {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s poll
          }
        }

        switch condition {
        case .appears:
          if found {
            return .result(.passed, detail: "'\(text)' appeared", screenshot: nil)
          }
          return .result(
            .failed, detail: "'\(text)' did not appear within \(maxWait)s", screenshot: nil)
        case .disappears:
          if !found {
            return .result(.passed, detail: "'\(text)' disappeared", screenshot: nil)
          }
          return .result(
            .failed, detail: "'\(text)' still present after \(maxWait)s", screenshot: nil)
        }

      case .verify(let condition):
        let result = await VerifyEngine.verify(condition, wdaClient: wdaClient)
        return .result(
          result.passed ? .passed : .failed,
          detail: result.detail,
          screenshot: nil
        )

      case .ifElementExists(let using, let value, let thenSteps):
        do {
          _ = try await wdaClient.findElement(using: using, value: value)
          // Element exists — run sub-steps inline
          for (j, subStep) in thenSteps.enumerated() {
            let subOutcome = await runStep(subStep, index: index * 100 + j)
            if case .result(.failed, _, _) = subOutcome, errorStrategy != .continue {
              return subOutcome
            }
          }
          return .result(
            .passed, detail: "Conditional branch executed (\(thenSteps.count) sub-steps)",
            screenshot: nil)
        } catch {
          return .result(
            .skipped, detail: "Element not found, skipped conditional branch", screenshot: nil)
        }

      case .judge(let question):
        let ss = await captureScreenshot()
        return .suspend(question: question, screenshot: ss)

      case .handleUnexpected(let description):
        let ss = await captureScreenshot()
        return .suspend(
          question: "Unexpected state: \(description). How should I proceed?", screenshot: ss)
      }
    } catch {
      return .result(.failed, detail: "\(error)", screenshot: nil)
    }
  }

  // MARK: - Helpers

  private func captureScreenshot() async -> String? {
    if #available(macOS 14.0, *) {
      do {
        let sim = try await session.resolveSimulator(nil)
        let result = try await FramebufferCapture.captureInline(
          simulator: sim, format: "jpeg", quality: 0.7)
        return result.base64
      } catch {
        return nil
      }
    }
    return nil
  }

  private func targetDescription(_ target: StepTarget) -> String {
    switch target {
    case .variable(let name): return "$\(name)"
    case .label(let text): return "'\(text)'"
    }
  }

  private func stepTypeName(_ step: PlanStep) -> String {
    switch step {
    case .navigate: return "navigate"
    case .navigateBack: return "navigateBack"
    case .find: return "find"
    case .findAll: return "findAll"
    case .click: return "click"
    case .doubleTap: return "doubleTap"
    case .longPress: return "longPress"
    case .swipe: return "swipe"
    case .typeText: return "typeText"
    case .screenshot: return "screenshot"
    case .wait: return "wait"
    case .waitFor: return "waitFor"
    case .verify: return "verify"
    case .ifElementExists: return "ifElementExists"
    case .judge: return "judge"
    case .handleUnexpected: return "handleUnexpected"
    }
  }

  private func swipeCoordinates(direction: String, width: Double, height: Double) -> (
    Double, Double, Double, Double
  ) {
    let cx = width / 2
    let cy = height / 2
    let dx = width * 0.35  // swipe distance = 70% of half-width
    let dy = height * 0.25  // swipe distance = 50% of half-height
    switch direction.lowercased() {
    case "up": return (cx, cy + dy, cx, cy - dy)
    case "down": return (cx, cy - dy, cx, cy + dy)
    case "left": return (cx + dx, cy, cx - dx, cy)
    case "right": return (cx - dx, cy, cx + dx, cy)
    default: return (cx, cy + dy, cx, cy - dy)
    }
  }
}
