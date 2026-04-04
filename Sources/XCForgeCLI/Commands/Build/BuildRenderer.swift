import Foundation
import XCForgeKit

enum BuildRenderer {
    static func renderBuild(_ execution: BuildTools.BuildExecution) -> String {
        var lines: [String] = []

        if execution.succeeded {
            lines.append("Build succeeded in \(execution.elapsed)s")
        } else {
            lines.append("Build FAILED in \(execution.elapsed)s")
        }

        lines.append("Scheme: \(execution.scheme)")
        lines.append("Simulator: \(execution.simulator)")
        lines.append("Configuration: \(execution.configuration)")

        if let bid = execution.bundleId {
            lines.append("Bundle ID: \(bid)")
        }
        if let path = execution.appPath {
            lines.append("App path: \(path)")
        }

        if !execution.succeeded, let reason = execution.failureReason {
            lines.append("Failure reason: \(reason)")
        }

        if let structured = execution.structuredErrors, !structured.isEmpty {
            lines.append("")
            lines.append("Errors (\(structured.count)):")
            for error in structured {
                lines.append("  \(error)")
            }
        } else if !execution.errors.isEmpty {
            lines.append("")
            lines.append("Errors (\(execution.errors.count)):")
            for error in execution.errors {
                lines.append("  \(error)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func renderDiagnose(_ execution: TestTools.BuildDiagnosisExecution) -> String {
        var lines: [String] = []

        let status = execution.succeeded ? "SUCCEEDED" : "FAILED"
        lines.append("Build \(status) in \(execution.elapsed)s")

        if execution.errorCount > 0 || execution.warningCount > 0 || execution.analyzerWarningCount > 0 {
            var parts: [String] = []
            if execution.errorCount > 0 { parts.append("\(execution.errorCount) error(s)") }
            if execution.warningCount > 0 { parts.append("\(execution.warningCount) warning(s)") }
            if execution.analyzerWarningCount > 0 { parts.append("\(execution.analyzerWarningCount) analyzer warning(s)") }
            lines.append(parts.joined(separator: ", "))
        }

        for issue in execution.issues.prefix(20) {
            let prefix: String
            switch issue.severity {
            case .error: prefix = "ERROR"
            case .warning: prefix = "WARNING"
            case .analyzerWarning: prefix = "ANALYZER"
            }

            var location = ""
            if let loc = issue.location {
                let shortPath = (loc.filePath as NSString).lastPathComponent
                location = " \(shortPath)"
                if let line = loc.line {
                    location += ":\(line)"
                    if let col = loc.column {
                        location += ":\(col)"
                    }
                }
            }

            lines.append("  \(prefix)\(location): \(issue.message)")
        }

        if let name = execution.destinationDeviceName, !name.isEmpty {
            let os = execution.destinationOSVersion ?? ""
            lines.append("Device: \(name) (\(os))")
        }

        lines.append("xcresult: \(execution.xcresultPath)")

        return lines.joined(separator: "\n")
    }

    static func renderClean(_ execution: BuildTools.CleanExecution) -> String {
        var lines: [String] = []

        if execution.succeeded {
            lines.append("Clean succeeded")
        } else {
            lines.append("Clean FAILED")
        }

        lines.append("Project: \(execution.project)")
        lines.append("Scheme: \(execution.scheme)")

        if let error = execution.error, !error.isEmpty {
            lines.append("")
            lines.append(error)
        }

        return lines.joined(separator: "\n")
    }

    static func renderDiscover(_ execution: BuildTools.DiscoverExecution) -> String {
        var lines: [String] = []

        if execution.projects.isEmpty {
            lines.append("No projects found in \(execution.path)")
        } else {
            lines.append("Found \(execution.projects.count) project(s) in \(execution.path):")
            for project in execution.projects {
                lines.append("  \(project)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func renderSchemes(_ execution: BuildTools.SchemesExecution) -> String {
        var lines: [String] = []

        if !execution.succeeded {
            lines.append("Failed to list schemes for \(execution.project)")
            if let error = execution.error, !error.isEmpty {
                lines.append(error)
            }
            return lines.joined(separator: "\n")
        }

        if execution.schemes.isEmpty {
            lines.append("No schemes found for \(execution.project)")
        } else {
            lines.append("Schemes for \(execution.project):")
            for scheme in execution.schemes {
                lines.append("  \(scheme)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
