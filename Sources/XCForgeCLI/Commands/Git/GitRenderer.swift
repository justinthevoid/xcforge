import Foundation

enum GitRenderer {
  static func render(_ result: GitResult) -> String {
    result.output
  }

  static func renderJSON(_ result: GitResult) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(result)
    guard let string = String(data: data, encoding: .utf8) else {
      throw EncodingError.invalidValue(
        result, .init(codingPath: [], debugDescription: "Failed to encode GitResult as UTF-8"))
    }
    return string
  }
}
