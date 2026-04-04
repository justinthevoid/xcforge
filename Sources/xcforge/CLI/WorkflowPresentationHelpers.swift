import Foundation
import xcforgeCore

enum WorkflowPresentationHelpers {
    static func phaseLabel(_ phase: WorkflowPhase?) -> String {
        guard let phase else { return "diagnosis" }

        switch phase {
        case .diagnosisStart:
            return "diagnosis setup"
        case .diagnosisBuild:
            return "build diagnosis"
        case .diagnosisTest:
            return "test diagnosis"
        case .diagnosisRuntime:
            return "runtime diagnosis"
        }
    }

    static func statusLabel(
        status: WorkflowStatus?,
        failure: WorkflowFailure?,
        recoveryHistory: [WorkflowRecoveryRecord]
    ) -> String {
        if failure != nil, status == nil {
            return "Result unavailable"
        }

        switch status {
        case .succeeded:
            return "Verified success"
        case .partial:
            return recoveryHistory.last?.resumed == false ? "Blocked by environment" : "Partial result"
        case .failed:
            return recoveryHistory.last?.resumed == false ? "Blocked by environment" : "Failed diagnosis"
        case .unsupported:
            return "Unsupported result"
        case .canceled:
            return "Canceled"
        case .inProgress:
            return "In progress"
        case nil:
            return "Result unavailable"
        }
    }

    static func evidenceSummary(for attempt: DiagnosisCompareAttemptSnapshot?) -> String {
        guard let attempt else {
            return "No attempt evidence is available in the final result."
        }

        let available = attempt.availableEvidence.count
        let unavailable = attempt.unavailableEvidence.count

        if available == 0 && unavailable == 0 {
            return "No evidence records were attached to this attempt."
        }

        return "\(available) available, \(unavailable) missing"
    }

    static func primaryProofCue(for attempt: DiagnosisCompareAttemptSnapshot?) -> String {
        guard let attempt else {
            return "No attempt snapshot is available for proof review."
        }

        if let artifact = preferredProofArtifact(from: attempt.availableEvidence) {
            return "Best available artifact: \(humanize(artifact.kind.rawValue)) from attempt \(artifact.attemptNumber)."
        }

        if let missing = attempt.unavailableEvidence.first {
            var cue = "Best available artifact is missing: \(humanize(missing.kind.rawValue)) for attempt \(missing.attemptNumber)"
            if let reason = missing.unavailableReasonLabel {
                cue += " (\(reason))"
            }
            return cue + "."
        }

        return "No proof artifact was identified for the current attempt."
    }

    static func nextReviewAction(for result: DiagnosisFinalResult) -> String {
        if result.failure != nil {
            return "Inspect Failure Details below."
        }

        if !result.recoveryHistory.isEmpty {
            return "Review Recovery Narrative below."
        }

        if result.comparison != nil || result.sourceAttempt != nil || result.sourceAttemptId != nil {
            return "Review Meaningful Change below."
        }

        if let currentAttempt = result.currentAttempt {
            if !currentAttempt.availableEvidence.isEmpty {
                return "Inspect Current Evidence Bundle below."
            }

            if !currentAttempt.unavailableEvidence.isEmpty {
                return "Review missing evidence notes in Current Evidence Bundle below."
            }

            return "Review Current Evidence Bundle below."
        }

        return "Review Run Context below."
    }

    static func humanize(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
    }

    static func missingDiagnosisExplanation(phase: WorkflowPhase?) -> String {
        let stepName: String
        switch phase {
        case .diagnosisBuild:
            stepName = "build diagnosis"
        case .diagnosisTest:
            stepName = "test diagnosis"
        case .diagnosisRuntime:
            stepName = "runtime diagnosis"
        case .diagnosisStart, nil:
            stepName = "diagnosis"
        }
        return "No diagnosis detail is available. Producing step: \(stepName)"
    }

    static func guidanceBlock(for result: DiagnosisFinalResult) -> [String] {
        guard let guidance = result.followOnAction else {
            return []
        }
        return [
            "Next Step",
            "  suggested_action: \(guidance.action)",
            "  rationale: \(guidance.rationale)",
            "  confidence: \(guidance.confidence.rawValue)",
        ]
    }

    static func statusPrefix(
        status: WorkflowStatus?,
        failure: WorkflowFailure?,
        recoveryHistory: [WorkflowRecoveryRecord]
    ) -> String {
        if failure != nil, status == nil {
            return "[UNAVAILABLE] "
        }

        let isBlocked = recoveryHistory.last?.resumed == false

        switch status {
        case .succeeded:
            return "[OK] "
        case .partial:
            return isBlocked ? "[BLOCKED] " : "[PARTIAL] "
        case .failed:
            return isBlocked ? "[BLOCKED] " : "[FAILED] "
        case .unsupported:
            return "[UNSUPPORTED] "
        case .canceled:
            return "[CANCELED] "
        case .inProgress:
            return "[IN PROGRESS] "
        case nil:
            return "[UNAVAILABLE] "
        }
    }

    static func formatEvidenceRecord(_ record: WorkflowEvidenceRecord, layout: TerminalLayout, indent: String = "    ") -> String {
        let reference: String
        if let recordReference = record.reference, !recordReference.isEmpty {
            reference = recordReference
        } else {
            reference = "<missing>"
        }

        switch layout {
        case .narrow:
            return [
                "\(indent)- \(record.kind.rawValue)",
                "\(indent)  phase: \(record.phase.rawValue)",
                "\(indent)  attempt: \(record.attemptNumber)",
                "\(indent)  state: \(record.availabilityLabel)",
                "\(indent)  source: \(record.source)",
                "\(indent)  reference: \(reference)",
            ].joined(separator: "\n")
        case .medium:
            return "\(indent)- \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber)"
                + "\n\(indent)  state=\(record.availabilityLabel) | source=\(record.source) | reference=\(reference)"
        case .wide:
            return "\(indent)- \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber) | state=\(record.availabilityLabel) | source=\(record.source) | reference=\(reference)"
        }
    }

    static func formatMissingEvidenceRecord(_ record: WorkflowEvidenceRecord, layout: TerminalLayout, indent: String = "    ") -> String {
        var fields: [(String, String)] = [
            ("phase", record.phase.rawValue),
            ("attempt", "\(record.attemptNumber)"),
            ("state", record.availabilityLabel),
            ("source", record.source),
            ("producing step", record.producingWorkflowStep),
        ]
        if let reason = record.unavailableReasonLabel {
            fields.append(("reason", reason))
        }
        if let detail = record.detail {
            fields.append(("detail", detail))
        }

        switch layout {
        case .narrow:
            var lines = ["\(indent)- \(record.kind.rawValue)"]
            lines += fields.map { "\(indent)  \($0.0): \($0.1)" }
            return lines.joined(separator: "\n")
        case .medium:
            let firstHalf = fields.prefix(3).map { "\($0.0)=\($0.1)" }.joined(separator: " | ")
            let secondHalf = fields.dropFirst(3).map { "\($0.0)=\($0.1)" }.joined(separator: " | ")
            var result = "\(indent)- \(record.kind.rawValue) | \(firstHalf)"
            if !secondHalf.isEmpty {
                result += "\n\(indent)  \(secondHalf)"
            }
            return result
        case .wide:
            let allFields = fields.map { "\($0.0)=\($0.1)" }.joined(separator: " | ")
            return "\(indent)- \(record.kind.rawValue) | \(allFields)"
        }
    }

    static func formatRecoveryRecord(_ recovery: WorkflowRecoveryRecord, layout: TerminalLayout, indent: String = "  ") -> String {
        let sanitize = { (value: String) -> String in
            value
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: " | ", with: " / ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch layout {
        case .narrow:
            var lines = [
                "\(indent)- \(recovery.recoveryId)",
                "\(indent)  issue: \(recovery.issue.label)",
                "\(indent)  action: \(recovery.action.label)",
                "\(indent)  status: \(recovery.status.rawValue)",
                "\(indent)  resumed: \(recovery.resumed ? "yes" : "no")",
                "\(indent)  detected: \(sanitize(recovery.detectedIssue))",
                "\(indent)  summary: \(sanitize(recovery.summary))",
            ]
            if let detail = recovery.detail {
                lines.append("\(indent)  detail: \(sanitize(detail))")
            }
            return lines.joined(separator: "\n")
        case .medium:
            let line1 = "\(indent)- \(recovery.recoveryId) | issue=\(recovery.issue.label) | action=\(recovery.action.label)"
            var line2 = "\(indent)  status=\(recovery.status.rawValue) | resumed=\(recovery.resumed ? "yes" : "no")"
            line2 += " | detected=\(sanitize(recovery.detectedIssue))"
            var line3 = "\(indent)  summary=\(sanitize(recovery.summary))"
            if let detail = recovery.detail {
                line3 += " | detail=\(sanitize(detail))"
            }
            return [line1, line2, line3].joined(separator: "\n")
        case .wide:
            var line = "\(indent)- \(recovery.recoveryId)"
            line += " | issue=\(recovery.issue.label)"
            line += " | action=\(recovery.action.label)"
            line += " | status=\(recovery.status.rawValue)"
            line += " | resumed=\(recovery.resumed ? "yes" : "no")"
            line += " | detected=\(sanitize(recovery.detectedIssue))"
            line += " | summary=\(sanitize(recovery.summary))"
            if let detail = recovery.detail {
                line += " | detail=\(sanitize(detail))"
            }
            return line
        }
    }

    private static func preferredProofArtifact(
        from evidence: [WorkflowEvidenceRecord]
    ) -> WorkflowEvidenceRecord? {
        evidence.first { record in
            switch record.kind {
            case .consoleLog, .screenshot, .xcresult, .stderr:
                return true
            case .buildSummary, .testSummary, .runtimeSummary:
                return false
            }
        } ?? evidence.first
    }
}
