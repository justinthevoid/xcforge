import Foundation

public enum WorkflowJSONRenderer {
  public static func renderJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    // Safe to force-unwrap: JSONEncoder always produces valid UTF-8.
    return String(data: data, encoding: .utf8)!
  }
}
