import ArgumentParser
import XCForgeKit

// `OutputAudience` is defined in XCForgeKit so the MCP dispatch path can thread
// it without depending on ArgumentParser. The CLI adds the ArgumentParser
// conformance here.
extension OutputAudience: ExpressibleByArgument {}
