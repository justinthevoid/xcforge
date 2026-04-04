import ArgumentParser
import Foundation
import XCForgeKit

struct Git: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "git",
        abstract: "Git operations for a repository.",
        subcommands: [GitStatus.self, GitDiff.self, GitLog.self, GitCommit.self, GitBranch.self],
        defaultSubcommand: GitStatus.self
    )
}

// MARK: - Codable result wrapper

struct GitResult: Codable {
    let succeeded: Bool
    let output: String
}

// MARK: - git status

struct GitStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show git status (porcelain format) for a repository."
    )

    @Option(help: "Repository path. Defaults to current directory.")
    var path: String = "."

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let path = self.path
        let json = self.json

        try runAsync {
            do {
                let result = try await Shell.git(["status", "--porcelain"], workingDirectory: path)
                let output = result.stdout.isEmpty ? "Working tree clean" : result.stdout
                let gitResult = GitResult(succeeded: true, output: output)

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }
            } catch {
                let gitResult = GitResult(succeeded: false, output: "Error: \(error)")

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }

                throw ExitCode.failure
            }
        }
    }
}

// MARK: - git diff

struct GitDiff: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Show git diff for a repository."
    )

    @Option(help: "Repository path. Defaults to current directory.")
    var path: String = "."

    @Flag(help: "Show staged changes only.")
    var staged = false

    @Option(help: "Optional specific file to diff.")
    var file: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let path = self.path
        let staged = self.staged
        let file = self.file
        let json = self.json

        try runAsync {
            do {
                var gitArgs = ["diff"]
                if staged { gitArgs.append("--cached") }
                if let f = file { gitArgs.append(f) }

                let result = try await Shell.git(gitArgs, workingDirectory: path)
                let rawOutput = result.stdout.isEmpty ? "No differences" : result.stdout
                let output = rawOutput.count > 50000 ? String(rawOutput.prefix(50000)) + "\n... [truncated]" : rawOutput
                let gitResult = GitResult(succeeded: true, output: output)

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }
            } catch {
                let gitResult = GitResult(succeeded: false, output: "Error: \(error)")

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }

                throw ExitCode.failure
            }
        }
    }
}

// MARK: - git log

struct GitLog: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Show recent git log entries."
    )

    @Option(help: "Repository path. Defaults to current directory.")
    var path: String = "."

    @Option(help: "Number of commits to show. Default: 10")
    var count: Int = 10

    @Flag(help: "One-line format. Default: true")
    var oneline = true

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let path = self.path
        let count = self.count
        let oneline = self.oneline
        let json = self.json

        try runAsync {
            do {
                var gitArgs = ["log", "-\(count)"]
                if oneline {
                    gitArgs.append("--oneline")
                } else {
                    gitArgs += ["--format=%H%n%an <%ae>%n%ai%n%s%n"]
                }

                let result = try await Shell.git(gitArgs, workingDirectory: path)
                let output = result.stdout.isEmpty ? "No commits" : result.stdout
                let gitResult = GitResult(succeeded: true, output: output)

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }
            } catch {
                let gitResult = GitResult(succeeded: false, output: "Error: \(error)")

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }

                throw ExitCode.failure
            }
        }
    }
}

// MARK: - git commit

struct GitCommit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "commit",
        abstract: "Create a git commit with staged changes."
    )

    @Option(help: "Repository path. Defaults to current directory.")
    var path: String = "."

    @Option(help: "Commit message.")
    var message: String

    @Flag(help: "Stage all changes before committing.")
    var addAll = false

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let path = self.path
        let message = self.message
        let addAll = self.addAll
        let json = self.json

        try runAsync {
            do {
                if addAll {
                    let addResult = try await Shell.git(["add", "-A"], workingDirectory: path)
                    if !addResult.succeeded {
                        let gitResult = GitResult(succeeded: false, output: "git add failed: \(addResult.stderr)")

                        if json {
                            print(try GitRenderer.renderJSON(gitResult))
                        } else {
                            print(GitRenderer.render(gitResult))
                        }

                        throw ExitCode.failure
                    }
                }

                let result = try await Shell.git(["commit", "-m", message], workingDirectory: path)
                if result.succeeded {
                    let gitResult = GitResult(succeeded: true, output: "Committed: \(result.stdout)")

                    if json {
                        print(try GitRenderer.renderJSON(gitResult))
                    } else {
                        print(GitRenderer.render(gitResult))
                    }
                } else {
                    let gitResult = GitResult(succeeded: false, output: "Commit failed: \(result.stderr)")

                    if json {
                        print(try GitRenderer.renderJSON(gitResult))
                    } else {
                        print(GitRenderer.render(gitResult))
                    }

                    throw ExitCode.failure
                }
            } catch let exitError as ExitCode {
                throw exitError
            } catch {
                let gitResult = GitResult(succeeded: false, output: "Error: \(error)")

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }

                throw ExitCode.failure
            }
        }
    }
}

// MARK: - git branch

struct GitBranch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "branch",
        abstract: "List, create, or switch git branches."
    )

    @Option(help: "Repository path. Defaults to current directory.")
    var path: String = "."

    @Option(help: "Action: list, create, switch. Default: list")
    var action: String = "list"

    @Option(help: "Branch name (for create/switch).")
    var name: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let path = self.path
        let action = self.action
        let name = self.name
        let json = self.json

        try runAsync {
            do {
                let gitResult: GitResult

                switch action {
                case "list":
                    let result = try await Shell.git(["branch", "-a"], workingDirectory: path)
                    let output = result.stdout.isEmpty ? "No branches" : result.stdout
                    gitResult = GitResult(succeeded: true, output: output)

                case "create":
                    guard let n = name else {
                        gitResult = GitResult(succeeded: false, output: "Missing branch name")

                        if json {
                            print(try GitRenderer.renderJSON(gitResult))
                        } else {
                            print(GitRenderer.render(gitResult))
                        }

                        throw ExitCode.validationFailure
                    }
                    let result = try await Shell.git(["checkout", "-b", n], workingDirectory: path)
                    gitResult = result.succeeded
                        ? GitResult(succeeded: true, output: "Created and switched to branch '\(n)'")
                        : GitResult(succeeded: false, output: result.stderr)

                case "switch":
                    guard let n = name else {
                        gitResult = GitResult(succeeded: false, output: "Missing branch name")

                        if json {
                            print(try GitRenderer.renderJSON(gitResult))
                        } else {
                            print(GitRenderer.render(gitResult))
                        }

                        throw ExitCode.validationFailure
                    }
                    let result = try await Shell.git(["checkout", n], workingDirectory: path)
                    gitResult = result.succeeded
                        ? GitResult(succeeded: true, output: "Switched to branch '\(n)'")
                        : GitResult(succeeded: false, output: result.stderr)

                default:
                    gitResult = GitResult(succeeded: false, output: "Unknown action: \(action). Use: list, create, switch")
                }

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }

                if !gitResult.succeeded {
                    throw ExitCode.failure
                }
            } catch let exitError as ExitCode {
                throw exitError
            } catch {
                let gitResult = GitResult(succeeded: false, output: "Error: \(error)")

                if json {
                    print(try GitRenderer.renderJSON(gitResult))
                } else {
                    print(GitRenderer.render(gitResult))
                }

                throw ExitCode.failure
            }
        }
    }
}
