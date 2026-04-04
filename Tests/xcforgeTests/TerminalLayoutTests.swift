import Foundation
import Testing
@testable import xcforge

@Suite("TerminalLayout")
struct TerminalLayoutTests {

    @Test("classify returns narrow for columns under 60")
    func classifyReturnsNarrowForColumnsUnder60() {
        #expect(TerminalLayout.classify(columns: 1) == .narrow)
        #expect(TerminalLayout.classify(columns: 40) == .narrow)
        #expect(TerminalLayout.classify(columns: 59) == .narrow)
    }

    @Test("classify returns medium for columns 60 through 99")
    func classifyReturnsMediumForColumns60Through99() {
        #expect(TerminalLayout.classify(columns: 60) == .medium)
        #expect(TerminalLayout.classify(columns: 80) == .medium)
        #expect(TerminalLayout.classify(columns: 99) == .medium)
    }

    @Test("classify returns wide for columns 100 and above")
    func classifyReturnsWideForColumns100AndAbove() {
        #expect(TerminalLayout.classify(columns: 100) == .wide)
        #expect(TerminalLayout.classify(columns: 200) == .wide)
    }

    @Test("classify returns wide when columns is nil")
    func classifyReturnsWideWhenColumnsIsNil() {
        #expect(TerminalLayout.classify(columns: nil) == .wide)
    }

    @Test("classify returns wide for zero and negative columns")
    func classifyReturnsWideForZeroAndNegativeColumns() {
        #expect(TerminalLayout.classify(columns: 0) == .wide)
        #expect(TerminalLayout.classify(columns: -1) == .wide)
        #expect(TerminalLayout.classify(columns: -100) == .wide)
    }
}
