import Foundation
import MCP

/// Decodes `[String: Value]?` MCP argument dictionaries into typed `Decodable` structs.
///
/// Matches the coercion behavior of the existing `Value` extensions (`numberValue`, `intValue`, `boolValue`):
/// - Numbers accept `.int`, `.double`, and parseable `.string` values
/// - Bools accept `.bool` and `.string` ("true"/"1")
/// - Optional fields decode as `nil` when absent or `.null`
enum ToolInput {

  /// Decode result that avoids requiring `Error` conformance on `CallTool.Result`.
  enum Decoded<T> {
    case success(T)
    case failure(CallTool.Result)
  }

  static func decode<T: Decodable>(_ type: T.Type, from args: [String: Value]?) -> Decoded<T> {
    do {
      let decoder = ValueArgumentDecoder(values: args ?? [:])
      return .success(try T(from: decoder))
    } catch let error as DecodingError {
      let message = Self.friendlyMessage(error)
      return .failure(.fail(message))
    } catch {
      return .failure(.fail("Invalid arguments: \(error)"))
    }
  }

  private static func friendlyMessage(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, _):
      return "Missing required: \(key.stringValue)"
    case .typeMismatch(let type, let ctx):
      let key = ctx.codingPath.last?.stringValue ?? "unknown"
      return "Invalid argument: \(key) (expected \(simpleName(type)))"
    case .valueNotFound(let type, let ctx):
      let key = ctx.codingPath.last?.stringValue ?? "unknown"
      return "Missing required: \(key) (expected \(simpleName(type)))"
    case .dataCorrupted(let ctx):
      let key = ctx.codingPath.last?.stringValue ?? "unknown"
      return "Invalid argument: \(key)"
    @unknown default:
      return "Invalid arguments"
    }
  }

  private static func simpleName(_ type: Any.Type) -> String {
    let name = String(describing: type)
    // Simplify common Swift type names for user-facing messages
    if name.contains("Int") { return "integer" }
    if name.contains("Double") || name.contains("Float") { return "number" }
    if name.contains("Bool") { return "boolean" }
    if name.contains("String") { return "string" }
    if name.contains("Array") { return "array" }
    return name.lowercased()
  }
}

// MARK: - ValueArgumentDecoder

private struct ValueArgumentDecoder: Decoder {
  let values: [String: Value]
  var codingPath: [CodingKey] = []
  var userInfo: [CodingUserInfoKey: Any] = [:]

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    KeyedDecodingContainer(ValueKeyedContainer(values: values, codingPath: codingPath))
  }

  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    throw DecodingError.typeMismatch(
      [Value].self, .init(codingPath: codingPath, debugDescription: "Expected keyed container"))
  }

  func singleValueContainer() throws -> SingleValueDecodingContainer {
    throw DecodingError.typeMismatch(
      Value.self, .init(codingPath: codingPath, debugDescription: "Expected keyed container"))
  }
}

// MARK: - KeyedDecodingContainer

private struct ValueKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let values: [String: Value]
  var codingPath: [CodingKey]
  var allKeys: [Key] { values.keys.compactMap { Key(stringValue: $0) } }

  func contains(_ key: Key) -> Bool { values[key.stringValue] != nil }

  func decodeNil(forKey key: Key) throws -> Bool {
    guard let val = values[key.stringValue] else { return true }
    return val == .null
  }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
    guard let val = values[key.stringValue] else { throw missing(key) }
    switch val {
    case .bool(let b): return b
    case .string(let s) where s == "true" || s == "1": return true
    case .string(let s) where s == "false" || s == "0": return false
    default: throw mismatch(type, key)
    }
  }

  func decode(_ type: String.Type, forKey key: Key) throws -> String {
    guard let val = values[key.stringValue] else { throw missing(key) }
    if case .string(let s) = val { return s }
    throw mismatch(type, key)
  }

  func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
    guard let val = values[key.stringValue] else { throw missing(key) }
    switch val {
    case .int(let n): return n
    case .double(let n): return Int(n)
    case .string(let s):
      if let d = Double(s) { return Int(d) }
      throw mismatch(type, key)
    default: throw mismatch(type, key)
    }
  }

  func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
    guard let val = values[key.stringValue] else { throw missing(key) }
    switch val {
    case .double(let n): return n
    case .int(let n): return Double(n)
    case .string(let s):
      if let d = Double(s) { return d }
      throw mismatch(type, key)
    default: throw mismatch(type, key)
    }
  }

  // Forward other numeric types through Double/Int
  func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
    Float(try decode(Double.self, forKey: key))
  }
  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
    Int8(try decode(Int.self, forKey: key))
  }
  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
    Int16(try decode(Int.self, forKey: key))
  }
  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
    Int32(try decode(Int.self, forKey: key))
  }
  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
    Int64(try decode(Int.self, forKey: key))
  }
  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
    UInt(try decode(Int.self, forKey: key))
  }
  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
    UInt8(try decode(Int.self, forKey: key))
  }
  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
    UInt16(try decode(Int.self, forKey: key))
  }
  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
    UInt32(try decode(Int.self, forKey: key))
  }
  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
    UInt64(try decode(Int.self, forKey: key))
  }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    guard let val = values[key.stringValue] else { throw missing(key) }
    if val == .null { throw missing(key) }

    // Direct Value passthrough — allows `steps: [Value]` in PlanTools
    if type == Value.self, let result = val as? T { return result }
    if type == [Value].self, case .array(let arr) = val, let result = arr as? T { return result }

    // Nested object
    if case .object(let dict) = val {
      let decoder = ValueArgumentDecoder(values: dict, codingPath: codingPath + [key])
      return try T(from: decoder)
    }

    // Array of decodable — try element-wise first, fall back to JSON round-trip
    // for types that use singleValueContainer (e.g. LogTools.IncludeTopics)
    if case .array(let arr) = val {
      do {
        let decoder = ValueArrayDecoder(values: arr, codingPath: codingPath + [key])
        return try T(from: decoder)
      } catch {
        let data = try JSONEncoder().encode(val)
        return try JSONDecoder().decode(T.self, from: data)
      }
    }

    // Fall back to JSON round-trip for complex types
    let data = try JSONEncoder().encode(val)
    return try JSONDecoder().decode(T.self, from: data)
  }

  func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    guard let val = values[key.stringValue], val != .null else { return nil }

    // Primitive fast paths for optionals
    if type == Bool.self || type == Optional<Bool>.self {
      return try decode(Bool.self, forKey: key) as? T
    }
    if type == String.self || type == Optional<String>.self {
      return try decode(String.self, forKey: key) as? T
    }
    if type == Int.self || type == Optional<Int>.self {
      return try decode(Int.self, forKey: key) as? T
    }
    if type == Double.self || type == Optional<Double>.self {
      return try decode(Double.self, forKey: key) as? T
    }

    return try decode(T.self, forKey: key)
  }

  func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
    -> KeyedDecodingContainer<NestedKey>
  {
    guard case .object(let dict) = values[key.stringValue] else {
      throw mismatch([String: Value].self, key)
    }
    return KeyedDecodingContainer(
      ValueKeyedContainer<NestedKey>(values: dict, codingPath: codingPath + [key]))
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
    guard case .array(let arr) = values[key.stringValue] else {
      throw mismatch([Value].self, key)
    }
    return ValueArrayDecodingContainer(values: arr, codingPath: codingPath + [key])
  }

  func superDecoder() throws -> Decoder {
    ValueArgumentDecoder(values: values, codingPath: codingPath)
  }

  func superDecoder(forKey key: Key) throws -> Decoder {
    guard case .object(let dict) = values[key.stringValue] else {
      throw mismatch([String: Value].self, key)
    }
    return ValueArgumentDecoder(values: dict, codingPath: codingPath + [key])
  }

  // MARK: - Error helpers

  private func missing(_ key: Key) -> DecodingError {
    .keyNotFound(
      key, .init(codingPath: codingPath, debugDescription: "Key '\(key.stringValue)' not found"))
  }

  private func mismatch(_ type: Any.Type, _ key: Key) -> DecodingError {
    .typeMismatch(
      type,
      .init(
        codingPath: codingPath + [key], debugDescription: "Type mismatch for '\(key.stringValue)'"))
  }
}

// MARK: - Array Decoder (for [Value] and [Decodable])

private struct ValueArrayDecoder: Decoder {
  let values: [Value]
  var codingPath: [CodingKey]
  var userInfo: [CodingUserInfoKey: Any] = [:]

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    throw DecodingError.typeMismatch(
      [String: Value].self, .init(codingPath: codingPath, debugDescription: "Expected array"))
  }

  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    ValueArrayDecodingContainer(values: values, codingPath: codingPath)
  }

  func singleValueContainer() throws -> SingleValueDecodingContainer {
    throw DecodingError.typeMismatch(
      Value.self, .init(codingPath: codingPath, debugDescription: "Expected array"))
  }
}

private struct ValueArrayDecodingContainer: UnkeyedDecodingContainer {
  let values: [Value]
  var codingPath: [CodingKey]
  var count: Int? { values.count }
  var isAtEnd: Bool { currentIndex >= values.count }
  var currentIndex: Int = 0

  private struct IndexKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ index: Int) {
      self.stringValue = "\(index)"
      self.intValue = index
    }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
      self.stringValue = "\(intValue)"
      self.intValue = intValue
    }
  }

  mutating func decodeNil() throws -> Bool {
    guard !isAtEnd else { return true }
    if values[currentIndex] == .null {
      currentIndex += 1
      return true
    }
    return false
  }

  mutating func decode(_ type: Bool.Type) throws -> Bool {
    let val = try next()
    switch val {
    case .bool(let b): return b
    case .string(let s) where s == "true" || s == "1": return true
    case .string(let s) where s == "false" || s == "0": return false
    default: throw typeMismatch(type)
    }
  }

  mutating func decode(_ type: String.Type) throws -> String {
    let val = try next()
    if case .string(let s) = val { return s }
    throw typeMismatch(type)
  }

  mutating func decode(_ type: Int.Type) throws -> Int {
    let val = try next()
    switch val {
    case .int(let n): return n
    case .double(let n): return Int(n)
    case .string(let s):
      if let d = Double(s) { return Int(d) }
      throw typeMismatch(type)
    default: throw typeMismatch(type)
    }
  }

  mutating func decode(_ type: Double.Type) throws -> Double {
    let val = try next()
    switch val {
    case .double(let n): return n
    case .int(let n): return Double(n)
    case .string(let s):
      if let d = Double(s) { return d }
      throw typeMismatch(type)
    default: throw typeMismatch(type)
    }
  }

  mutating func decode(_ type: Float.Type) throws -> Float { Float(try decode(Double.self)) }
  mutating func decode(_ type: Int8.Type) throws -> Int8 { Int8(try decode(Int.self)) }
  mutating func decode(_ type: Int16.Type) throws -> Int16 { Int16(try decode(Int.self)) }
  mutating func decode(_ type: Int32.Type) throws -> Int32 { Int32(try decode(Int.self)) }
  mutating func decode(_ type: Int64.Type) throws -> Int64 { Int64(try decode(Int.self)) }
  mutating func decode(_ type: UInt.Type) throws -> UInt { UInt(try decode(Int.self)) }
  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { UInt8(try decode(Int.self)) }
  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { UInt16(try decode(Int.self)) }
  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { UInt32(try decode(Int.self)) }
  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { UInt64(try decode(Int.self)) }

  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let val = try next()
    if type == Value.self, let result = val as? T { return result }
    if case .object(let dict) = val {
      return try T(from: ValueArgumentDecoder(values: dict, codingPath: codingPath))
    }
    let data = try JSONEncoder().encode(val)
    return try JSONDecoder().decode(T.self, from: data)
  }

  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws
    -> KeyedDecodingContainer<NestedKey>
  {
    let val = try next()
    guard case .object(let dict) = val else { throw typeMismatch([String: Value].self) }
    return KeyedDecodingContainer(
      ValueKeyedContainer<NestedKey>(values: dict, codingPath: codingPath))
  }

  mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
    let val = try next()
    guard case .array(let arr) = val else { throw typeMismatch([Value].self) }
    return ValueArrayDecodingContainer(values: arr, codingPath: codingPath)
  }

  mutating func superDecoder() throws -> Decoder {
    let val = try next()
    guard case .object(let dict) = val else { throw typeMismatch([String: Value].self) }
    return ValueArgumentDecoder(values: dict, codingPath: codingPath)
  }

  private mutating func next() throws -> Value {
    guard !isAtEnd else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: codingPath, debugDescription: "Unkeyed container is at end"))
    }
    let val = values[currentIndex]
    currentIndex += 1
    return val
  }

  private func typeMismatch(_ type: Any.Type) -> DecodingError {
    .typeMismatch(
      type,
      .init(
        codingPath: codingPath + [IndexKey(currentIndex - 1)],
        debugDescription: "Type mismatch at index \(currentIndex - 1)"))
  }
}
