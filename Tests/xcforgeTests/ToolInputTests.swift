import MCP
import Testing

@testable import xcforgeCore

@Suite("ToolInput: ValueArgumentDecoder")
struct ToolInputTests {
    // MARK: - Test Input Structs

    struct RequiredFields: Decodable {
        let name: String
        let count: Int
    }

    struct OptionalFields: Decodable {
        let name: String?
        let count: Int?
        let active: Bool?
        let threshold: Double?
    }

    struct MixedFields: Decodable {
        let path: String
        let staged: Bool?
        let file: String?
    }

    struct CoordinateFields: Decodable {
        let x: Double
        let y: Double
    }

    struct ArrayField: Decodable {
        let tags: [String]?
    }

    // MARK: - Happy Path

    @Test("decodes required string and int fields")
    func requiredFieldsPresent() {
        let args: [String: Value] = ["name": .string("hello"), "count": .int(5)]
        let result = ToolInput.decode(RequiredFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.name == "hello")
            #expect(input.count == 5)
        case .failure:
            Issue.record("Expected success")
        }
    }

    @Test("decodes all optional fields when present")
    func optionalFieldsPresent() {
        let args: [String: Value] = [
            "name": .string("test"),
            "count": .int(3),
            "active": .bool(true),
            "threshold": .double(0.5),
        ]
        let result = ToolInput.decode(OptionalFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.name == "test")
            #expect(input.count == 3)
            #expect(input.active == true)
            #expect(input.threshold == 0.5)
        case .failure:
            Issue.record("Expected success")
        }
    }

    @Test("optional fields default to nil when absent")
    func optionalFieldsAbsent() {
        let args: [String: Value] = [:]
        let result = ToolInput.decode(OptionalFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.name == nil)
            #expect(input.count == nil)
            #expect(input.active == nil)
            #expect(input.threshold == nil)
        case .failure:
            Issue.record("Expected success")
        }
    }

    // MARK: - Missing Required

    @Test("fails with friendly message for missing required string")
    func missingRequiredString() {
        let args: [String: Value] = ["count": .int(5)]
        let result = ToolInput.decode(RequiredFields.self, from: args)
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let callResult):
            let text = extractText(callResult)
            #expect(text.contains("Missing required: name"))
        }
    }

    @Test("fails for nil args dict when required fields exist")
    func nilArgsDictRequired() {
        let result = ToolInput.decode(RequiredFields.self, from: nil)
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let callResult):
            let text = extractText(callResult)
            #expect(text.contains("Missing required"))
        }
    }

    // MARK: - Type Coercion (matching numberValue/intValue/boolValue extensions)

    @Test("Int field accepts Value.double via coercion")
    func intFromDouble() {
        let args: [String: Value] = ["name": .string("x"), "count": .double(42.0)]
        let result = ToolInput.decode(RequiredFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.count == 42)
        case .failure:
            Issue.record("Expected success — Int should accept .double")
        }
    }

    @Test("Int field accepts Value.string via coercion")
    func intFromString() {
        let args: [String: Value] = ["name": .string("x"), "count": .string("7")]
        let result = ToolInput.decode(RequiredFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.count == 7)
        case .failure:
            Issue.record("Expected success — Int should accept parseable .string")
        }
    }

    @Test("Double field accepts Value.int via coercion")
    func doubleFromInt() {
        let args: [String: Value] = ["x": .int(10), "y": .int(20)]
        let result = ToolInput.decode(CoordinateFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.x == 10.0)
            #expect(input.y == 20.0)
        case .failure:
            Issue.record("Expected success — Double should accept .int")
        }
    }

    @Test("Double field accepts Value.string via coercion")
    func doubleFromString() {
        let args: [String: Value] = ["x": .string("3.14"), "y": .string("2.71")]
        let result = ToolInput.decode(CoordinateFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.x == 3.14)
            #expect(input.y == 2.71)
        case .failure:
            Issue.record("Expected success — Double should accept parseable .string")
        }
    }

    @Test("Bool field accepts string 'true' and '1'")
    func boolFromString() {
        let args1: [String: Value] = ["name": .string("x"), "count": .int(1), "active": .string("true"), "threshold": .double(0.0)]
        let result1 = ToolInput.decode(OptionalFields.self, from: args1)
        switch result1 {
        case .success(let input): #expect(input.active == true)
        case .failure: Issue.record("Expected success — Bool should accept 'true' string")
        }

        let args2: [String: Value] = ["active": .string("1")]
        let result2 = ToolInput.decode(OptionalFields.self, from: args2)
        switch result2 {
        case .success(let input): #expect(input.active == true)
        case .failure: Issue.record("Expected success — Bool should accept '1' string")
        }
    }

    // MARK: - Extra Unknown Args (silently ignored)

    @Test("extra keys in args dict are silently ignored")
    func extraKeysIgnored() {
        let args: [String: Value] = [
            "path": .string("/repo"),
            "staged": .bool(true),
            "unknown_key": .string("should be ignored"),
            "another_extra": .int(999),
        ]
        let result = ToolInput.decode(MixedFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.path == "/repo")
            #expect(input.staged == true)
            #expect(input.file == nil)
        case .failure:
            Issue.record("Expected success — extra keys should be ignored")
        }
    }

    // MARK: - Null Values

    @Test("null values decode as nil for optional fields")
    func nullValuesAreNil() {
        let args: [String: Value] = ["name": .null, "count": .null]
        let result = ToolInput.decode(OptionalFields.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.name == nil)
            #expect(input.count == nil)
        case .failure:
            Issue.record("Expected success — .null should decode as nil")
        }
    }

    // MARK: - Type Mismatch

    @Test("wrong type produces descriptive error")
    func wrongType() {
        let args: [String: Value] = ["name": .int(42), "count": .int(5)]
        let result = ToolInput.decode(RequiredFields.self, from: args)
        switch result {
        case .success:
            Issue.record("Expected failure — String field got Int")
        case .failure(let callResult):
            let text = extractText(callResult)
            #expect(text.contains("Invalid argument: name"))
        }
    }

    // MARK: - Custom Decoder with singleValueContainer (array-or-string)

    struct IncludeWrapper: Decodable {
        let include: FlexibleArray?

        struct FlexibleArray: Decodable {
            let values: [String]

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let arr = try? container.decode([String].self) {
                    values = arr
                } else if let single = try? container.decode(String.self) {
                    values = [single]
                } else {
                    values = []
                }
            }
        }
    }

    @Test("custom singleValueContainer decoder works with array input")
    func flexibleArrayFromArray() {
        let args: [String: Value] = ["include": .array([.string("app"), .string("network")])]
        let result = ToolInput.decode(IncludeWrapper.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.include?.values == ["app", "network"])
        case .failure:
            Issue.record("Expected success — array input for singleValueContainer decoder")
        }
    }

    @Test("custom singleValueContainer decoder works with string input")
    func flexibleArrayFromString() {
        let args: [String: Value] = ["include": .string("crashes")]
        let result = ToolInput.decode(IncludeWrapper.self, from: args)
        switch result {
        case .success(let input):
            #expect(input.include?.values == ["crashes"])
        case .failure:
            Issue.record("Expected success — string input for singleValueContainer decoder")
        }
    }

    // MARK: - Helpers

    private func extractText(_ result: CallTool.Result) -> String {
        result.content.compactMap {
            if case .text(let text, _, _) = $0 { return text }
            return nil
        }.joined()
    }
}
