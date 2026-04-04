import Foundation

/// Compile-time stability manifest for xcforge workflow result contracts.
///
/// This file exists to break compilation when stable contract assumptions are violated.
/// It references actual types and constants so that renaming, removing, or changing
/// any guaranteed-stable surface causes a compiler error rather than a silent
/// runtime regression.
public enum StableWorkflowContract {

  // MARK: - Stable Field Descriptor

  public struct StableField: Sendable, Equatable {
    public let keyPath: String
    public let description: String
  }

  // MARK: - Compile-Time Type Anchors

  /// Anchored to the type of `WorkflowRunRecord.currentSchemaVersion`.
  public static var schemaVersion: String.Type {
    type(of: WorkflowRunRecord.currentSchemaVersion)
  }

  public static var workflowName: WorkflowName.Type {
    WorkflowName.self
  }

  public static var workflowStatus: WorkflowStatus.Type {
    WorkflowStatus.self
  }

  public static var workflowPhase: WorkflowPhase.Type {
    WorkflowPhase.self
  }

  public static var failureClassification: WorkflowFailureClassification.Type {
    WorkflowFailureClassification.self
  }

  public static var verifyOutcome: DiagnosisVerifyOutcome.Type {
    DiagnosisVerifyOutcome.self
  }

  public static var compareOutcome: DiagnosisCompareOutcome.Type {
    DiagnosisCompareOutcome.self
  }

  public static var evidenceState: DiagnosisEvidenceState.Type {
    DiagnosisEvidenceState.self
  }

  public static var followOnConfidence: FollowOnConfidence.Type {
    FollowOnConfidence.self
  }

  public static var inspectEvidenceCompleteness: DiagnosisInspectEvidenceCompleteness.Type {
    DiagnosisInspectEvidenceCompleteness.self
  }

  // MARK: - Supported Result Types

  /// All MVP result types. Removing or renaming any type breaks compilation.
  public static let supportedResultTypeCount = 10
  public static let allSupportedResultTypes: [any Codable.Type] = [
    DiagnosisStartResult.self,
    DiagnosisBuildResult.self,
    DiagnosisTestResult.self,
    DiagnosisRuntimeResult.self,
    DiagnosisStatusResult.self,
    DiagnosisVerifyResult.self,
    DiagnosisCompareResult.self,
    DiagnosisFinalResult.self,
    DiagnosisEvidenceResult.self,
    DiagnosisInspectResult.self,
  ]

  // MARK: - Guaranteed Stable Fields

  /// Fields present across all result types. These key paths are contractually
  /// stable and must not be renamed or removed without a major version bump.
  public static let guaranteedStableFields: [StableField] = [
    StableField(
      keyPath: "schemaVersion",
      description: "Semantic version string matching WorkflowRunRecord.currentSchemaVersion"
    ),
    StableField(
      keyPath: "workflow",
      description: "WorkflowName identifying which workflow produced the result"
    ),
    StableField(
      keyPath: "status",
      description: "WorkflowStatus indicating outcome (may be optional on some types)"
    ),
    StableField(
      keyPath: "failure",
      description: "Optional WorkflowFailure with classification and message"
    ),
    StableField(
      keyPath: "runId",
      description: "Optional unique identifier for the workflow run"
    ),
    StableField(
      keyPath: "attemptId",
      description: "Optional unique identifier for the specific attempt"
    ),
    StableField(
      keyPath: "persistedRunPath",
      description: "Optional filesystem path where the run record was persisted"
    ),
  ]
}
