import Foundation
import Testing

@testable import XCForgeCLI

@Suite("CLI help with piped output")
struct CLIHelpTests {

  /// The error a help request ends in: thrown by the parser, or by the help command it returns.
  private func helpError(_ arguments: [String]) -> Error? {
    do {
      let command = try XCForgeCLI.parseAsRoot(arguments)
      guard String(describing: type(of: command)) == "HelpCommand" else { return nil }
      var help = command
      try help.run()
      return nil
    } catch {
      return error
    }
  }

  @Test("help requests are never printed as JSON errors")
  func helpIsNotAJSONError() throws {
    for arguments in [["--help"], ["build", "--help"], ["ui", "tap", "-h"], ["help", "ui", "tap"]] {
      let error = try #require(helpError(arguments), "no help error for \(arguments)")
      #expect(XCForgeCLI.exitCode(for: error) == .success)
      #expect(!printJSONError(error), "\(arguments) became a JSON error")
    }
  }

  /// The CLI binary `swift build` leaves next to the test bundle's build folder.
  static var binary: String? {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let root = tests.deletingLastPathComponent().deletingLastPathComponent()
    let candidates = ["XCForgeCLI", "xcforge"].map { root.appendingPathComponent(".build/debug/\($0)").path }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  @Test("--help with stdout piped prints usage and exits 0", .enabled(if: CLIHelpTests.binary != nil))
  func pipedHelp() throws {
    for arguments in [["--help"], ["build", "--help"], ["help", "ui", "tap"]] {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: try #require(Self.binary))
      process.arguments = arguments
      let stdout = Pipe()
      process.standardOutput = stdout
      process.standardError = Pipe()
      try process.run()
      let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      process.waitUntilExit()
      #expect(process.terminationStatus == 0, "\(arguments) exited \(process.terminationStatus): \(output)")
      #expect(output.contains("USAGE"), "\(arguments) printed: \(output)")
      #expect(!output.contains("\"code\""))
    }
  }
}
