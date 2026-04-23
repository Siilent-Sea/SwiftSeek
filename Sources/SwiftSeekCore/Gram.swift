import Foundation

public enum Gram {
    public static let size = 3

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
}
