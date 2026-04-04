import Foundation

public struct RunStore: Sendable {
  public let baseDirectory: URL

  public init(baseDirectory: URL? = nil) {
    if let baseDirectory {
      self.baseDirectory = baseDirectory
      return
    }

    if let override = ProcessInfo.processInfo.environment["XCFORGE_RUN_STORE_DIR"],
      !override.isEmpty
    {
      let expanded = (override as NSString).expandingTildeInPath
      self.baseDirectory = URL(fileURLWithPath: expanded, isDirectory: true)
      return
    }

    self.baseDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .appendingPathComponent(".xcforge", isDirectory: true)
      .appendingPathComponent("runs", isDirectory: true)
  }

  public func save(_ run: WorkflowRunRecord) throws -> URL {
    try FileManager.default.createDirectory(
      at: baseDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let fileURL = runFileURL(runId: run.runId)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(run)
    try data.write(to: fileURL, options: .atomic)
    return fileURL
  }

  public func load(runId: String) throws -> WorkflowRunRecord {
    let fileURL = runFileURL(runId: runId)
    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(WorkflowRunRecord.self, from: data)
  }

  public func update(_ run: WorkflowRunRecord) throws -> URL {
    try save(run)
  }

  public func listRuns() throws -> [WorkflowRunRecord] {
    guard FileManager.default.directoryExists(at: baseDirectory.path) else {
      return []
    }

    let fileURLs = try FileManager.default.contentsOfDirectory(
      at: baseDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var runs: [WorkflowRunRecord] = []
    for url in fileURLs where url.pathExtension == "json" {
      guard let run = try? Self.decodeRun(at: url, decoder: decoder) else {
        continue
      }
      runs.append(run)
    }
    return runs
  }

  public func listDiagnosisRuns() throws -> [WorkflowRunRecord] {
    try listRuns()
      .filter { $0.workflow == .diagnosis }
      .sorted(by: Self.sortByRecency)
  }

  public func latestActiveDiagnosisRun() throws -> WorkflowRunRecord? {
    try listDiagnosisRuns().first { $0.status == .inProgress }
  }

  public func latestTerminalDiagnosisRun() throws -> WorkflowRunRecord? {
    try listDiagnosisRuns().first {
      $0.status != .inProgress
        && ($0.phase == .diagnosisBuild || $0.phase == .diagnosisTest
          || $0.phase == .diagnosisRuntime)
    }
  }

  public func latestDiagnosisRun() throws -> WorkflowRunRecord? {
    try listDiagnosisRuns().first
  }

  public func reusableDiagnosisRun(runId: String? = nil) throws -> WorkflowRunRecord? {
    if let runId {
      let run = try load(runId: runId)
      guard run.workflow == .diagnosis else {
        throw RunStoreError.invalidReusableDiagnosisRun(
          runId: runId,
          workflow: run.workflow.rawValue
        )
      }
      return run
    }

    if let activeRun = try latestActiveDiagnosisRun() {
      return activeRun
    }

    return try latestDiagnosisRun()
  }

  public func runFileURL(runId: String) -> URL {
    baseDirectory.appendingPathComponent("\(runId).json", isDirectory: false)
  }

  public func evidenceFileURL(runId: String, attemptId: String, name: String, ext: String) -> URL {
    baseDirectory
      .appendingPathComponent("\(runId)-\(attemptId)-\(name)", isDirectory: false)
      .appendingPathExtension(ext)
  }

  private static func sortByRecency(lhs: WorkflowRunRecord, rhs: WorkflowRunRecord) -> Bool {
    if lhs.updatedAt != rhs.updatedAt {
      return lhs.updatedAt > rhs.updatedAt
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt > rhs.createdAt
    }
    return lhs.runId > rhs.runId
  }

  private static func decodeRun(at url: URL, decoder: JSONDecoder) throws -> WorkflowRunRecord {
    let data = try Data(contentsOf: url)
    return try decoder.decode(WorkflowRunRecord.self, from: data)
  }
}

private enum RunStoreError: LocalizedError {
  case invalidReusableDiagnosisRun(runId: String, workflow: String)

  var errorDescription: String? {
    switch self {
    case .invalidReusableDiagnosisRun(let runId, let workflow):
      return
        "Run \(runId) is a \(workflow) workflow record and cannot seed diagnosis context reuse."
    }
  }
}

extension FileManager {
  fileprivate func directoryExists(at path: String) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
  }
}
