import Foundation
import xcforgeCore

enum DiagnosisStartRenderer {
    static func render(_ result: DiagnosisStartResult) -> String {
        var lines: [String] = [
            "Workflow: \(result.workflow.rawValue)",
            "Phase: \(result.phase.rawValue)",
            "Status: \(result.status.rawValue)",
        ]

        if let runId = result.runId {
            lines.append("Run ID: \(runId)")
        }
        if let attemptId = result.attemptId {
            lines.append("Attempt ID: \(attemptId)")
        }

        if let context = result.resolvedContext {
            lines.append("Resolved context:")
            lines.append("  project: \(context.project)")
            lines.append("  scheme: \(context.scheme)")
            lines.append("  simulator: \(context.simulator)")
            lines.append("  configuration: \(context.configuration)")
            lines.append("  bundle_id: \(context.app.bundleId)")
            lines.append("  app_path: \(context.app.appPath)")
            if let preparation = context.simulatorPreparation {
                lines.append("Prepared simulator:")
                lines.append("  requested: \(preparation.requested)")
                lines.append("  target: \(preparation.selected)")
                lines.append("  name: \(preparation.displayName)")
                lines.append("  runtime: \(preparation.runtime)")
                lines.append("  initial_state: \(preparation.initialState)")
                lines.append("  state: \(preparation.state)")
                lines.append("  action: \(preparation.action.rawValue)")
                lines.append("  summary: \(preparation.summary)")
            }
        }

        if let provenance = result.contextProvenance {
            lines.append(contentsOf: renderContextProvenance(provenance))
        }

        if let preflight = result.environmentPreflight {
            lines.append("Environment preflight: \(preflight.status.rawValue)")
            lines.append("Preflight summary: \(preflight.summary)")
            if !preflight.checks.isEmpty {
                lines.append("Preflight checks:")
                lines += preflight.checks.map {
                    "  - \($0.kind.rawValue): \($0.status.rawValue) — \($0.message)"
                }
            }
        }

        if let persistedRunPath = result.persistedRunPath {
            lines.append("Run record: \(persistedRunPath)")
        }

        if let failure = result.failure {
            lines.append("Failure field: \(failure.field.rawValue)")
            lines.append("Failure class: \(failure.classification.rawValue)")
            lines.append("Reason: \(failure.message)")
            if !failure.options.isEmpty {
                lines.append("Options:")
                lines += failure.options.map { "  - \($0)" }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func renderContextProvenance(_ provenance: WorkflowContextProvenance) -> [String] {
        var lines: [String] = ["Context provenance:"]

        if let sourceRunId = provenance.sourceRunId {
            if let sourceAttemptId = provenance.sourceAttemptId {
                lines.append("  source run: \(sourceRunId) (attempt \(sourceAttemptId))")
            } else {
                lines.append("  source run: \(sourceRunId)")
            }
        }

        for field in provenance.fields {
            lines.append("  \(label(for: field.field)): \(label(for: field))")
        }

        return lines
    }

    private static func label(for field: WorkflowContextFieldProvenance) -> String {
        switch field.source {
        case .explicit:
            return "explicit override"
        case .reusedRun:
            if let sourceRunId = field.sourceRunId {
                return "reused from run \(sourceRunId)"
            }
            return "reused from source run"
        case .sessionDefault:
            return "session default"
        case .workflowDefault:
            return "workflow default"
        case .autoDetected:
            return "auto-detected"
        case .derived:
            if let detail = field.detail {
                return "derived (\(detail))"
            }
            return "derived"
        }
    }

    private static func label(for field: ContextField) -> String {
        switch field {
        case .build:
            return "configuration"
        default:
            return field.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }
}
