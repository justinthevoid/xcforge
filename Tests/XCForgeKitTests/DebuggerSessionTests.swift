import MCP
import Testing

@testable import XCForgeKit

// MARK: - parseBreakpointOutput Tests

@Suite("DebuggerProvider.parseBreakpointOutput")
struct ParseBreakpointOutputTests {

  @Test func returnsNilForEmptyOutput() {
    let result = DebuggerProvider.parseBreakpointOutput("")
    #expect(result == nil)
  }

  @Test func returnsNilForNoBreakpointLine() {
    let output = "error: No such file or directory\nsome other output"
    let result = DebuggerProvider.parseBreakpointOutput(output)
    #expect(result == nil)
  }

  @Test func parsesBreakpointIdFromStandardOutput() {
    let output =
      "Breakpoint 1: where = MyApp`ViewController.viewDidLoad() + 28 at ViewController.swift:42, address = 0xdeadbeef"
    let result = DebuggerProvider.parseBreakpointOutput(output)
    #expect(result == 1)
  }

  @Test func parsesBreakpointIdFromMultiLocationOutput() {
    let output = "Breakpoint 5: 3 locations."
    let result = DebuggerProvider.parseBreakpointOutput(output)
    #expect(result == 5)
  }

  @Test func parsesHighBreakpointId() {
    let output = "Breakpoint 42: where = SomeModule`foo() at bar.swift:10"
    let result = DebuggerProvider.parseBreakpointOutput(output)
    #expect(result == 42)
  }

  @Test func returnsNilForBreakpointZero() {
    // "Breakpoint 0" is invalid — LLDB does not use ID 0; nil is expected.
    let output = "Breakpoint 0: some malformed output"
    let result = DebuggerProvider.parseBreakpointOutput(output)
    #expect(result == nil)
  }

  @Test func returnsNilWhenLineContainsUnrelatedBreakpointWord() {
    let output = "This has no breakpoint IDs in the expected format"
    let result = DebuggerProvider.parseBreakpointOutput(output)
    #expect(result == nil)
  }

  @Test func multiLineOutputPicksFirstBreakpoint() {
    let output = """
      Breakpoint 3: where = App`AppDelegate.application(_:didFinishLaunchingWithOptions:) + 28
      Breakpoint 3: 1 locations.
      """
    let result = DebuggerProvider.parseBreakpointOutput(output)
    #expect(result == 3)
  }
}

// MARK: - parseContinueOutput Tests

@Suite("DebuggerProvider.parseContinueOutput")
struct ParseContinueOutputTests {

  @Test func detectsBreakpointStopReason() {
    let output = """
      Process 1234 stopped
      * thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 1.1
          frame #0: 0xdeadbeef MyApp`ViewController.viewDidLoad() at ViewController.swift:42
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "breakpoint")
  }

  @Test func detectsStepStopReason() {
    let output = """
      Process 1234 stopped
      * thread #1, stop reason = step over
          frame #0: 0x0000000100001234 MyApp`foo() at Foo.swift:10
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "step")
  }

  @Test func detectsSignalStopReason() {
    let output = """
      Process 1234 stopped
      * thread #1, stop reason = signal SIGINT
          frame #0: 0xdeadbeef MyApp`main at main.swift:1
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "signal")
  }

  @Test func detectsExitStopReason() {
    let output = "Process 1234 exited with status = 0 (0x00000000)"
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "exit")
  }

  @Test func detectsExceptionStopReason() {
    let output = """
      Process 1234 stopped
      * thread #1, stop reason = exception EXC_BAD_ACCESS
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "exit")
  }

  @Test func unknownStopReason() {
    let output = "Process 1234 continued"
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "unknown")
  }

  // Critical regression test: "step" must NOT match symbol names containing the word.
  @Test func doesNotMatchStepInSymbolName() {
    // A symbol like "stepForward" should not trigger "step" stop reason detection
    let output = """
      Process 1234 stopped
      * thread #1, stop reason = breakpoint 2.1
          frame #0: 0xdeadbeef MyApp`MyClass.stepForward() at MyClass.swift:50
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    // breakpoint should win — not "step" from the symbol name
    #expect(result.stopReason == "breakpoint")
  }

  @Test func doesNotMatchStepInsteadOfBreakpoint() {
    // Ensure loose "step" matching doesn't override the correct breakpoint reason
    let output = """
      Process stopped
      * thread #1, stop reason = breakpoint 1.1
          frame #0: 0x1234 App`MyController.stepCount() at VC.swift:100
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "breakpoint")
  }

  @Test func parsesThreadIndex() {
    let output = """
      Process 1234 stopped
      * thread #3, stop reason = breakpoint 1.1
          frame #0: 0xdeadbeef MyApp`foo() at bar.swift:10
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.threadIndex == 2)  // LLDB thread #3 is zero-based index 2
  }

  @Test func parsesFrameIndex() {
    let output = """
      Process 1234 stopped
      * thread #1, stop reason = step over
        * frame #2: 0xdeadbeef MyApp`foo() at bar.swift:10
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.frameIndex == 2)
  }
}

// MARK: - DebuggerSessionRegistry Tests

@Suite("DebuggerSessionRegistry")
struct DebuggerSessionRegistryTests {

  @Test func lookupThrowsNotFoundForUnknownId() async throws {
    let registry = DebuggerSessionRegistry()
    do {
      _ = try await registry.lookupSession(for: "nonexistent-id")
      #expect(Bool(false), "Expected notFound error")
    } catch let error as DebuggerRegistryError {
      if case .notFound(let id) = error {
        #expect(id == "nonexistent-id")
      } else {
        #expect(Bool(false), "Wrong error case: \(error)")
      }
    }
  }

  @Test func syncSessionThrowsNotFoundForUnknownId() async throws {
    let registry = DebuggerSessionRegistry()
    do {
      // session(for:) is actor-isolated; must call it within an actor context via await
      _ = try await registry.lookupSession(for: "missing-id")
      #expect(Bool(false), "Expected notFound error")
    } catch let error as DebuggerRegistryError {
      if case .notFound = error {
        // Expected
      } else {
        #expect(Bool(false), "Wrong error case")
      }
    }
  }

  @Test func removeIsSilentForUnknownId() async {
    let registry = DebuggerSessionRegistry()
    // Must not throw or crash
    await registry.remove(id: "does-not-exist")
  }

  @Test func notFoundErrorMessageMatchesSpec() async throws {
    let registry = DebuggerSessionRegistry()
    do {
      _ = try await registry.lookupSession(for: "stale-id")
    } catch let error as DebuggerRegistryError {
      // Spec requires "Session not found or expired" in the error message
      #expect(error.description.contains("Session not found or expired"))
    }
  }
}

// MARK: - parseBacktraceOutput Tests

@Suite("DebuggerProvider.parseBacktraceOutput")
struct ParseBacktraceOutputTests {

  @Test func parsesEmptyOutput() {
    let frames = DebuggerProvider.parseBacktraceOutput("")
    #expect(frames.isEmpty)
  }

  @Test func parsesSimpleFrame() {
    let output = """
      * thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint
          frame #0: 0x0000000100001234 MyApp`ViewController.viewDidLoad() at ViewController.swift:42
      """
    let frames = DebuggerProvider.parseBacktraceOutput(output)
    #expect(frames.count == 1)
    #expect(frames[0].frameIndex == 0)
    #expect(frames[0].file == "ViewController.swift")
    #expect(frames[0].line == 42)
  }

  @Test func parsesMultipleFrames() {
    let output = """
        frame #0: 0x0000000100001234 MyApp`foo() at Foo.swift:10
        frame #1: 0x0000000100001300 MyApp`bar() at Bar.swift:20
        frame #2: 0x0000000100001400 MyApp`baz() at Baz.swift:30
      """
    let frames = DebuggerProvider.parseBacktraceOutput(output)
    #expect(frames.count == 3)
    #expect(frames[0].frameIndex == 0)
    #expect(frames[1].frameIndex == 1)
    #expect(frames[2].frameIndex == 2)
  }

  @Test func parsesFrameWithoutFileInfo() {
    let output = "    frame #0: 0xdeadbeef libsystem`__pthread_start + 4"
    let frames = DebuggerProvider.parseBacktraceOutput(output)
    #expect(frames.count == 1)
    #expect(frames[0].file == nil)
    #expect(frames[0].line == nil)
  }
}

// MARK: - Newline Injection Guard Tests

@Suite("DebuggerProvider newline sanitization")
struct NewlineSanitizationTests {

  @Test func inspectVariableRejectsNewlineInExpression() async {
    let args: [String: Value] = [
      "sessionId": .string("fake-id"),
      "expression": .string("foo\nbar"),
    ]
    // The method checks for newlines before looking up the session.
    let result = await DebuggerProvider.performInspectVariable(args)
    #expect(result.isError == true)
    let text: String = {
      guard let first = result.content.first else { return "" }
      if case .text(let t, _, _) = first { return t }
      return ""
    }()
    #expect(text.contains("Newlines not allowed in expression"))
  }

  @Test func breakpointSetRejectsNewlineInFunction() async {
    let args: [String: Value] = [
      "sessionId": .string("fake-id"),
      "function": .string("foo\nrm -rf /"),
    ]
    let result = await DebuggerProvider.performSetBreakpoint(args)
    #expect(result.isError == true)
    let text: String = {
      guard let first = result.content.first else { return "" }
      if case .text(let t, _, _) = first { return t }
      return ""
    }()
    #expect(text.contains("Newlines not allowed in function"))
  }
}

// MARK: - parseContinueOutput multi-line Tests

@Suite("DebuggerProvider.parseContinueOutput multi-line")
struct ParseContinueOutputMultiLineTests {

  @Test func extractsStopReasonFromMultiLineBTOutput() {
    // Simulate LLDB `bt` output that includes preamble lines before the stop-reason line.
    let output = """
      Process 5678 resuming
      Process 5678 stopped
      * thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 3.1
          frame #0: 0x0000000100002345 MyApp`ViewController.loadView() at ViewController.swift:88
          frame #1: 0x0000000100003456 MyApp`AppDelegate.application(_:didFinishLaunchingWithOptions:) at AppDelegate.swift:20
          frame #2: 0x00007fff2345abcd UIKitCore`UIApplicationMain + 1621
      """
    let result = DebuggerProvider.parseContinueOutput(output)
    #expect(result.stopReason == "breakpoint")
    #expect(result.threadIndex == 0)  // thread #1 → zero-based index 0
    #expect(result.frameIndex == 0)  // * frame #0
  }
}
