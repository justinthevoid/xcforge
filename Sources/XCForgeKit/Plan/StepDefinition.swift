import Foundation
import MCP

// MARK: - Step Target

/// A reference to a UI element — either a `$variable` binding or a literal label/accessibility ID.
public enum StepTarget: Sendable {
  case variable(String)  // "$loginBtn"
  case label(String)  // "Login"

  public init(_ raw: String) {
    if raw.hasPrefix("$") {
      self = .variable(String(raw.dropFirst()))
    } else {
      self = .label(raw)
    }
  }
}

// MARK: - Verify Condition

public enum VerifyCondition: Sendable {
  case screenContains(String)
  case elementLabel(id: String, op: LabelOp, expected: String)
  case elementExists(using: String, value: String)
  case elementNotExists(using: String, value: String)
  case elementCount(using: String, value: String, op: CountOp, expected: Int)

  public enum LabelOp: String, Sendable { case equals, contains }
  public enum CountOp: String, Sendable { case equals, gte }
}

// MARK: - Wait Condition

public enum WaitCondition: Sendable {
  case appears
  case disappears
}

// MARK: - Error Strategy

public enum ErrorStrategy: String, Sendable {
  case abortWithScreenshot = "abort_with_screenshot"
  case abort
  case `continue`
}

// MARK: - Plan Step

public enum PlanStep: Sendable {
  case navigate(bundleId: String)
  case navigateBack
  case find(target: String, using: String?, bindAs: String?)
  case findAll(targets: [(label: String, bindAs: String?)], using: String?)
  case click(StepTarget)
  case doubleTap(StepTarget)
  case longPress(StepTarget, durationMs: Int?)
  case swipe(direction: String, target: StepTarget?, durationMs: Int?)
  case typeText(text: String, target: StepTarget?)
  case screenshot(label: String?)
  case wait(seconds: Double)
  case waitFor(text: String, timeout: Double?, condition: WaitCondition)
  case verify(VerifyCondition)
  case ifElementExists(using: String, value: String, then: [PlanStep])
  case judge(question: String)
  case handleUnexpected(description: String)
}

// MARK: - Parser

public enum PlanParser {
  public enum ParseError: Error, LocalizedError {
    case emptyStep(index: Int)
    case unknownStepType(index: Int, key: String)
    case missingField(index: Int, step: String, field: String)
    case invalidVerifyCondition(index: Int)
    case invalidValue(index: Int, detail: String)

    public var errorDescription: String? {
      switch self {
      case .emptyStep(let i): return "Step \(i): empty object"
      case .unknownStepType(let i, let k): return "Step \(i): unrecognized key '\(k)'"
      case .missingField(let i, let s, let f): return "Step \(i) (\(s)): missing '\(f)'"
      case .invalidVerifyCondition(let i): return "Step \(i): invalid verify condition"
      case .invalidValue(let i, let d): return "Step \(i): \(d)"
      }
    }
  }

  /// Known step keys in priority order for first-key-wins discriminator.
  private static let knownKeys: [String] = [
    "navigate", "navigateBack", "find", "findAll", "click", "doubleTap",
    "longPress", "swipe", "typeText", "screenshot", "wait", "waitFor",
    "verify", "ifElementExists", "judge", "handleUnexpected",
  ]

  public static func parse(_ steps: [Value]) throws -> [PlanStep] {
    try steps.enumerated().map { i, value in
      try parseStep(value, index: i)
    }
  }

  private static func parseStep(_ value: Value, index i: Int) throws -> PlanStep {
    // Value must be an object — extract its keys
    guard let obj = value.objectValue, !obj.isEmpty else {
      throw ParseError.emptyStep(index: i)
    }

    // First-key-wins: check known keys in order
    guard let matchedKey = knownKeys.first(where: { obj[$0] != nil }) else {
      let firstKey = obj.keys.first ?? "?"
      throw ParseError.unknownStepType(index: i, key: firstKey)
    }

    switch matchedKey {
    case "navigate":
      guard let bundleId = obj["navigate"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "navigate", field: "navigate")
      }
      return .navigate(bundleId: bundleId)

    case "navigateBack":
      return .navigateBack

    case "find":
      guard let target = obj["find"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "find", field: "find")
      }
      let using = obj["using"]?.stringValue
      let bindAs = obj["as"]?.stringValue
      return .find(target: target, using: using, bindAs: bindAs)

    case "findAll":
      guard let arr = obj["findAll"]?.arrayValue else {
        throw ParseError.missingField(index: i, step: "findAll", field: "findAll")
      }
      let targets: [(label: String, bindAs: String?)] = arr.compactMap { item in
        if let s = item.stringValue { return (label: s, bindAs: nil) }
        if let o = item.objectValue, let l = o["label"]?.stringValue {
          return (label: l, bindAs: o["as"]?.stringValue)
        }
        return nil
      }
      let using = obj["using"]?.stringValue
      return .findAll(targets: targets, using: using)

    case "click":
      guard let raw = obj["click"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "click", field: "click")
      }
      return .click(StepTarget(raw))

    case "doubleTap":
      guard let raw = obj["doubleTap"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "doubleTap", field: "doubleTap")
      }
      return .doubleTap(StepTarget(raw))

    case "longPress":
      guard let raw = obj["longPress"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "longPress", field: "longPress")
      }
      let dur = obj["duration_ms"]?.intValue
      return .longPress(StepTarget(raw), durationMs: dur)

    case "swipe":
      guard let dir = obj["swipe"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "swipe", field: "swipe")
      }
      let target = obj["on"]?.stringValue.map(StepTarget.init)
      let dur = obj["duration_ms"]?.intValue
      return .swipe(direction: dir, target: target, durationMs: dur)

    case "typeText":
      guard let text = obj["typeText"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "typeText", field: "typeText")
      }
      let target = obj["into"]?.stringValue.map(StepTarget.init)
      return .typeText(text: text, target: target)

    case "screenshot":
      let label = obj["screenshot"]?.stringValue
      return .screenshot(label: label == "" ? nil : label)

    case "wait":
      guard let secs = obj["wait"]?.doubleValue else {
        throw ParseError.invalidValue(index: i, detail: "wait requires a number (seconds)")
      }
      return .wait(seconds: secs)

    case "waitFor":
      guard let text = obj["waitFor"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "waitFor", field: "waitFor")
      }
      let timeout = obj["timeout"]?.doubleValue
      let condStr = obj["condition"]?.stringValue ?? "appears"
      let cond: WaitCondition = condStr == "disappears" ? .disappears : .appears
      return .waitFor(text: text, timeout: timeout, condition: cond)

    case "verify":
      let cond = try parseVerifyCondition(obj["verify"], index: i)
      return .verify(cond)

    case "ifElementExists":
      guard let value = obj["ifElementExists"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "ifElementExists", field: "ifElementExists")
      }
      let using = obj["using"]?.stringValue ?? "accessibility id"
      guard let thenArr = obj["then"]?.arrayValue else {
        throw ParseError.missingField(index: i, step: "ifElementExists", field: "then")
      }
      let thenSteps = try parse(thenArr)
      return .ifElementExists(using: using, value: value, then: thenSteps)

    case "judge":
      guard let q = obj["judge"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "judge", field: "judge")
      }
      return .judge(question: q)

    case "handleUnexpected":
      guard let desc = obj["handleUnexpected"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "handleUnexpected", field: "handleUnexpected")
      }
      return .handleUnexpected(description: desc)

    default:
      throw ParseError.unknownStepType(index: i, key: matchedKey)
    }
  }

  private static func parseVerifyCondition(_ value: Value?, index i: Int) throws -> VerifyCondition
  {
    // Can be an object with one key
    guard let obj = value?.objectValue else {
      // Or a string shorthand for screenContains
      if let text = value?.stringValue {
        return .screenContains(text)
      }
      throw ParseError.invalidVerifyCondition(index: i)
    }

    if let text = obj["screenContains"]?.stringValue {
      return .screenContains(text)
    }

    if let idObj = obj["elementLabel"]?.objectValue {
      guard let id = idObj["id"]?.stringValue,
        let expected = idObj["expected"]?.stringValue
      else {
        throw ParseError.missingField(index: i, step: "verify.elementLabel", field: "id/expected")
      }
      let opStr = idObj["op"]?.stringValue ?? "equals"
      let op: VerifyCondition.LabelOp = opStr == "contains" ? .contains : .equals
      return .elementLabel(id: id, op: op, expected: expected)
    }

    if let existsObj = obj["elementExists"]?.objectValue {
      let using = existsObj["using"]?.stringValue ?? "accessibility id"
      guard let val = existsObj["value"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "verify.elementExists", field: "value")
      }
      return .elementExists(using: using, value: val)
    }

    if let notObj = obj["elementNotExists"]?.objectValue {
      let using = notObj["using"]?.stringValue ?? "accessibility id"
      guard let val = notObj["value"]?.stringValue else {
        throw ParseError.missingField(index: i, step: "verify.elementNotExists", field: "value")
      }
      return .elementNotExists(using: using, value: val)
    }

    if let countObj = obj["elementCount"]?.objectValue {
      let using = countObj["using"]?.stringValue ?? "accessibility id"
      guard let val = countObj["value"]?.stringValue,
        let expected = countObj["expected"]?.intValue
      else {
        throw ParseError.missingField(
          index: i, step: "verify.elementCount", field: "value/expected")
      }
      let opStr = countObj["op"]?.stringValue ?? "equals"
      let op: VerifyCondition.CountOp = opStr == "gte" ? .gte : .equals
      return .elementCount(using: using, value: val, op: op, expected: expected)
    }

    throw ParseError.invalidVerifyCondition(index: i)
  }
}

// MARK: - Value Helpers (objectValue/arrayValue/doubleValue only — stringValue, intValue, boolValue live in UITools)

extension Value {
  var objectValue: [String: Value]? {
    if case .object(let dict) = self { return dict }
    return nil
  }

  var arrayValue: [Value]? {
    if case .array(let arr) = self { return arr }
    return nil
  }

  var doubleValue: Double? {
    if case .double(let d) = self { return d }
    if case .int(let i) = self { return Double(i) }
    return nil
  }
}
