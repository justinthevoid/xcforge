import Foundation
import Testing

@testable import XCForgeKit

@Suite("FuzzyMatch")
struct FuzzyMatchTests {
  @Test("exact match returns distance 0")
  func exactMatch() {
    let results = FuzzyMatch.fuzzyRank(needle: "testFoo", candidates: ["testFoo", "testBar"])
    #expect(results.first?.candidate == "testFoo")
    #expect(results.first?.distance == 0)
  }

  @Test("single transposition is within threshold")
  func singleTransposition() {
    // "testFooo" vs "testFoo" → distance 1, threshold = max(2, 8/3) = max(2, 2) = 2
    let results = FuzzyMatch.fuzzyRank(needle: "testFooo", candidates: ["testFoo"])
    #expect(!results.isEmpty)
    #expect(results.first?.distance == 1)
  }

  @Test("empty needle returns empty results")
  func emptyNeedle() {
    let results = FuzzyMatch.fuzzyRank(needle: "", candidates: ["testFoo", "testBar"])
    #expect(results.isEmpty)
  }

  @Test("candidate beyond threshold is excluded")
  func thresholdFiltering() {
    // "abc" needle: threshold = max(2, 1) = 2
    // "zzzzz" distance from "abc" = 5, which exceeds threshold
    // Also candidate length 5 > needle.count * 2 = 6, so within length limit but distance fails
    let results = FuzzyMatch.fuzzyRank(needle: "abc", candidates: ["zzzzz", "abd"])
    let candidates = results.map(\.candidate)
    #expect(!candidates.contains("zzzzz"))
    #expect(candidates.contains("abd"))
  }

  @Test("maxResults caps returned count")
  func maxResultsCap() {
    // "aa" with many close candidates — threshold = max(2, 0) = 2
    let candidates = ["ab", "ac", "ad", "ae", "af"]
    let results = FuzzyMatch.fuzzyRank(needle: "aa", candidates: candidates, maxResults: 3)
    #expect(results.count <= 3)
  }

  @Test("results sorted by distance ascending")
  func sortedAscending() {
    // needle "test", candidates at various distances
    let results = FuzzyMatch.fuzzyRank(
      needle: "test",
      candidates: ["tset", "test", "tes"],
      maxResults: 5
    )
    guard results.count >= 2 else { return }
    for i in 0..<(results.count - 1) {
      #expect(results[i].distance <= results[i + 1].distance)
    }
  }

  @Test("candidate longer than 2x needle is excluded")
  func lengthFilter() {
    // needle "ab" (length 2), max candidate length = 4
    // "abcdefgh" (length 8) should be excluded
    let results = FuzzyMatch.fuzzyRank(needle: "ab", candidates: ["abcdefgh", "abc"])
    let candidates = results.map(\.candidate)
    #expect(!candidates.contains("abcdefgh"))
  }
}
