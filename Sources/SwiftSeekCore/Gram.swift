import Foundation

public enum Gram {
    public static let size = 3
    /// F1: bigram size for the short-query hot path. A separate constant (not
    /// just `n = 2`) so callers and schema stay consistent about the index
    /// granularity.
    public static let bigramSize = 2

    /// Sliding-window 3-grams over Unicode characters. Returns an empty set if
    /// the input has fewer than `size` characters — callers must arrange a
    /// short-query fallback themselves.
    public static func grams(of text: String, n: Int = size) -> Set<String> {
        guard n > 0 else { return [] }
        let chars = Array(text)
        guard chars.count >= n else { return [] }
        var out: Set<String> = []
        out.reserveCapacity(chars.count - n + 1)
        for i in 0...(chars.count - n) {
            out.insert(String(chars[i..<(i + n)]))
        }
        return out
    }

    /// Union of 3-grams from a file's lowercase name and lowercase full path.
    /// Path grams allow queries like "docs/alpha" to narrow candidates via the
    /// gram index instead of a full table scan.
    public static func indexGrams(nameLower: String, pathLower: String) -> Set<String> {
        grams(of: nameLower).union(grams(of: pathLower))
    }

    /// F1: bigrams (2-grams) — a shorter-grained companion index used by the
    /// 2-character query hot path. Returns an empty set for single-character
    /// inputs, so callers must still have a 1-character fallback.
    public static func bigrams(of text: String) -> Set<String> {
        return grams(of: text, n: bigramSize)
    }

    /// F1: union of bigrams from lowercase name and lowercase path. Mirrors
    /// `indexGrams` so callers can populate the `file_bigrams` table the
    /// same way they populate `file_grams`.
    public static func indexBigrams(nameLower: String, pathLower: String) -> Set<String> {
        bigrams(of: nameLower).union(bigrams(of: pathLower))
    }
}
