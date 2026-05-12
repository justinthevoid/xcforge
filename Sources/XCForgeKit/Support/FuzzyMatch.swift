import Foundation

public enum FuzzyMatch {
  /// Rank candidates against a needle using Levenshtein distance.
  /// Only includes candidates where distance ≤ max(2, needle.count / 3)
  /// and candidate length is within 2× of needle length.
  /// Returns up to `maxResults` results sorted by distance ascending.
  public static func fuzzyRank(
    needle: String,
    candidates: [String],
    maxResults: Int = 3
  ) -> [(candidate: String, distance: Int)] {
    guard !needle.isEmpty else { return [] }
    let threshold = max(2, needle.count / 3)
    let maxCandidateLen = needle.count * 2

    var ranked: [(candidate: String, distance: Int)] = []
    for candidate in candidates {
      guard candidate.count <= maxCandidateLen else { continue }
      let d = levenshtein(needle, candidate)
      guard d <= threshold else { continue }
      ranked.append((candidate, d))
    }
    return Array(ranked.sorted { $0.distance < $1.distance }.prefix(maxResults))
  }

  // MARK: - Private

  private static func levenshtein(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)
    let m = aChars.count
    let n = bChars.count

    if m == 0 { return n }
    if n == 0 { return m }

    var prev = Array(0...n)
    var curr = [Int](repeating: 0, count: n + 1)

    for i in 1...m {
      curr[0] = i
      for j in 1...n {
        if aChars[i - 1] == bChars[j - 1] {
          curr[j] = prev[j - 1]
        } else {
          curr[j] = 1 + min(prev[j - 1], prev[j], curr[j - 1])
        }
      }
      swap(&prev, &curr)
    }
    return prev[n]
  }
}
