import Foundation

public struct IndexProgress {
    public let scanned: Int
    public let inserted: Int
    public let currentPath: String

    public init(scanned: Int, inserted: Int, currentPath: String) {
        self.scanned = scanned
        self.inserted = inserted
        self.currentPath = currentPath
    }
}

public struct IndexStats: CustomStringConvertible {
    public let rootPath: String
    public let scanned: Int
    public let inserted: Int
    public let skipped: Int
    public let cancelled: Bool
    public let durationSeconds: Double

    public init(rootPath: String,
                scanned: Int,
                inserted: Int,
                skipped: Int,
                cancelled: Bool,
                durationSeconds: Double) {
        self.rootPath = rootPath
        self.scanned = scanned
        self.inserted = inserted
        self.skipped = skipped
        self.cancelled = cancelled
        self.durationSeconds = durationSeconds
    }

    public var description: String {
        let state = cancelled ? "CANCELLED" : "DONE"
        return String(
            format: "[%@] root=%@ scanned=%d inserted=%d skipped=%d time=%.2fs",
            state, rootPath, scanned, inserted, skipped, durationSeconds
        )
    }
}
