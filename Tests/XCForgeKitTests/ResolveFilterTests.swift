import Testing

@testable import XCForgeKit

@Suite("resolveFilter bracket-aware slash counting")
struct ResolveFilterTests {

    // MARK: - slashComponentCount

    @Test func plainTwoComponents() {
        #expect(TestTools.slashComponentCount("Class/testMethod") == 2)
    }

    @Test func plainThreeComponents() {
        #expect(TestTools.slashComponentCount("Target/Class/testMethod") == 3)
    }

    @Test func singleComponent() {
        #expect(TestTools.slashComponentCount("testMethod") == 1)
    }

    @Test func emptyString() {
        #expect(TestTools.slashComponentCount("") == 1)
    }

    @Test func parameterizedWithSlash() {
        // "MyTests/testParse[path/to/file]" has 1 unbracketed slash → 2 components
        #expect(TestTools.slashComponentCount("MyTests/testParse[path/to/file]") == 2)
    }

    @Test func parameterizedWithMultipleSlashes() {
        // "Suite/test[a/b/c]" has 1 unbracketed slash → 2 components
        #expect(TestTools.slashComponentCount("Suite/test[a/b/c]") == 2)
    }

    @Test func nestedBrackets() {
        // "A/B[x[y/z]/w]" — nested brackets, slashes inside are ignored
        #expect(TestTools.slashComponentCount("A/B[x[y/z]/w]") == 2)
    }

    @Test func qualifiedWithParameterizedSlash() {
        // "Target/Class/test[a/b]" has 2 unbracketed slashes → 3 components
        #expect(TestTools.slashComponentCount("Target/Class/test[a/b]") == 3)
    }

    @Test func noSlashesInsideBrackets() {
        // "Target/Class/test[abc]" — brackets but no slashes inside
        #expect(TestTools.slashComponentCount("Target/Class/test[abc]") == 3)
    }

    @Test func unmatchedOpenBracket() {
        // "A/B[x/y" — unmatched bracket, slashes after [ still treated as inside
        #expect(TestTools.slashComponentCount("A/B[x/y") == 2)
    }

    @Test func unmatchedCloseBracket() {
        // "A/B]x/y" — unmatched close bracket ignored, slash counted normally
        #expect(TestTools.slashComponentCount("A/B]x/y") == 3)
    }

    @Test func slashOnlyInsideBrackets() {
        // "test[a/b/c/d]" — all slashes inside brackets → 1 component
        #expect(TestTools.slashComponentCount("test[a/b/c/d]") == 1)
    }
}
