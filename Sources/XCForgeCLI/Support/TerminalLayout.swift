import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum TerminalLayout: String, Sendable {
    case narrow
    case medium
    case wide

    static func detect() -> TerminalLayout {
        let columns = detectColumns()
        return classify(columns: columns)
    }

    static func classify(columns: Int?) -> TerminalLayout {
        guard let columns, columns > 0 else { return .wide }
        if columns < 60 { return .narrow }
        if columns < 100 { return .medium }
        return .wide
    }

    private static func detectColumns() -> Int? {
        if let env = ProcessInfo.processInfo.environment["COLUMNS"],
           let value = Int(env), value > 0 {
            return value
        }

        #if os(macOS) || os(Linux)
        var size = winsize()
        let result = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size)
        if result == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        #endif

        return nil
    }
}
